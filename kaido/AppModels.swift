//
//  AppModels.swift
//  gee
//
//  Created by Pluie on 23/04/2026.
//

import Foundation
import SwiftData

enum AppModelSchema {
    static let models: [any PersistentModel.Type] = [
        ProjectFolder.self,
        ProjectTemplate.self,
        TemplateStep.self,
        TemplateLink.self,
        Project.self,
        ProjectStep.self,
        ProjectLink.self,
        ProjectEvent.self,
    ]

    static var schema: Schema {
        Schema(models)
    }
}

enum ProjectStepStatus: String, Codable, CaseIterable, Identifiable {
    case todo
    case planned
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo:
            "Todo"
        case .planned:
            "Planned"
        case .done:
            "Done"
        }
    }

    var countsTowardProgress: Bool {
        self == .planned || self == .done
    }

    var next: ProjectStepStatus {
        switch self {
        case .todo:
            .planned
        case .planned:
            .done
        case .done:
            .todo
        }
    }

}

enum ProjectScheduleWarningLevel: Equatable {
    case warning
    case critical
}

struct ProjectScheduleWarning: Equatable {
    let level: ProjectScheduleWarningLevel
    let daysUntilStart: Int
}

@Model
final class ProjectFolder {
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Project.folder)
    var projects: [Project]

    init(name: String, createdAt: Date = .now, projects: [Project] = []) {
        self.name = name
        self.createdAt = createdAt
        self.projects = projects
    }
}

@Model
final class ProjectTemplate {
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TemplateStep.template)
    var steps: [TemplateStep]

    @Relationship(deleteRule: .cascade, inverse: \TemplateLink.template)
    var links: [TemplateLink]

    init(name: String, createdAt: Date = .now, steps: [TemplateStep] = [], links: [TemplateLink] = []) {
        self.name = name
        self.createdAt = createdAt
        self.steps = steps
        self.links = links
    }

    var orderedSteps: [TemplateStep] {
        steps.sortedBySortOrder()
    }

    var orderedLinks: [TemplateLink] {
        links.sortedBySortOrder()
    }
}

@Model
final class TemplateStep {
    var name: String
    var sortOrder: Int
    var template: ProjectTemplate?

    init(name: String, sortOrder: Int) {
        self.name = name
        self.sortOrder = sortOrder
    }
}

@Model
final class TemplateLink {
    var name: String
    var sortOrder: Int
    var template: ProjectTemplate?

    init(name: String, sortOrder: Int) {
        self.name = name
        self.sortOrder = sortOrder
    }
}

@Model
final class Project {
    var name: String
    var startDate: Date?
    var templateName: String
    var createdAt: Date
    var archivedAt: Date?
    var ongoingStartedAt: Date?
    var folder: ProjectFolder?

    @Relationship(deleteRule: .cascade, inverse: \ProjectStep.project)
    var steps: [ProjectStep]

    @Relationship(deleteRule: .cascade, inverse: \ProjectLink.project)
    var links: [ProjectLink]

    @Relationship(deleteRule: .cascade, inverse: \ProjectEvent.project)
    var events: [ProjectEvent]

    init(
        name: String,
        startDate: Date? = nil,
        templateName: String,
        createdAt: Date = .now,
        archivedAt: Date? = nil,
        ongoingStartedAt: Date? = nil,
        folder: ProjectFolder? = nil,
        steps: [ProjectStep] = [],
        links: [ProjectLink] = [],
        events: [ProjectEvent] = []
    ) {
        self.name = name
        self.startDate = startDate
        self.templateName = templateName
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.ongoingStartedAt = ongoingStartedAt
        self.folder = folder
        self.steps = steps
        self.links = links
        self.events = events
    }

    convenience init(name: String, startDate: Date? = nil, template: ProjectTemplate) {
        self.init(name: name, startDate: startDate, templateName: template.name)
        let copiedSteps = template.orderedSteps.enumerated().map { index, step in
            ProjectStep(title: step.name, sortOrder: index)
        }
        let copiedLinks = template.orderedLinks.enumerated().map { index, link in
            ProjectLink(name: link.name, sortOrder: index)
        }
        copiedSteps.forEach { $0.project = self }
        copiedLinks.forEach { $0.project = self }
        self.steps = copiedSteps
        self.links = copiedLinks
    }

    var orderedSteps: [ProjectStep] {
        steps.sortedBySortOrder()
    }

    var orderedLinks: [ProjectLink] {
        links.sortedBySortOrder()
    }

    var orderedEvents: [ProjectEvent] {
        events.sorted {
            if $0.eventDate == $1.eventDate {
                if $0.sortOrder == $1.sortOrder {
                    return $0.persistentModelID.hashValue < $1.persistentModelID.hashValue
                }

                return $0.sortOrder < $1.sortOrder
            }

            return $0.eventDate > $1.eventDate
        }
    }

    var isArchived: Bool {
        archivedAt != nil
    }

    var isOngoing: Bool {
        ongoingStartedAt != nil
    }

    var totalProgressItems: Int {
        steps.count + links.count
    }

    var completedProgressItems: Int {
        steps.filter(\.isProgressComplete).count + links.filter(\.hasValidURL).count
    }

    var progress: Double {
        guard totalProgressItems > 0 else {
            return 0
        }

        return Double(completedProgressItems) / Double(totalProgressItems)
    }

    func scheduleWarning(relativeTo referenceDate: Date = .now, calendar: Calendar = .current) -> ProjectScheduleWarning? {
        guard let startDate,
              isArchived == false,
              isOngoing == false,
              completedProgressItems < totalProgressItems else {
            return nil
        }

        let referenceDay = calendar.startOfDay(for: referenceDate)
        let startDay = calendar.startOfDay(for: startDate)
        guard let daysUntilStart = calendar.dateComponents([.day], from: referenceDay, to: startDay).day,
              daysUntilStart <= 15 else {
            return nil
        }

        let level: ProjectScheduleWarningLevel = daysUntilStart <= 7 ? .critical : .warning
        return ProjectScheduleWarning(level: level, daysUntilStart: daysUntilStart)
    }

    func scheduleWarningLevel(relativeTo referenceDate: Date = .now, calendar: Calendar = .current) -> ProjectScheduleWarningLevel? {
        scheduleWarning(relativeTo: referenceDate, calendar: calendar)?.level
    }
}

@Model
final class ProjectStep {
    var title: String
    var sortOrder: Int
    var scheduledDate: Date?
    var statusRawValue: String
    var project: Project?

    init(
        title: String,
        sortOrder: Int,
        scheduledDate: Date? = nil,
        status: ProjectStepStatus = .todo
    ) {
        self.title = title
        self.sortOrder = sortOrder
        self.scheduledDate = scheduledDate
        self.statusRawValue = status.rawValue
    }

    var status: ProjectStepStatus {
        get {
            ProjectStepStatus(rawValue: statusRawValue) ?? .todo
        }
        set {
            statusRawValue = newValue.rawValue
        }
    }

    var isProgressComplete: Bool {
        status.countsTowardProgress
    }
}

@Model
final class ProjectLink {
    var name: String
    var urlString: String
    var sortOrder: Int
    var project: Project?

    init(name: String, urlString: String = "", sortOrder: Int) {
        self.name = name
        self.urlString = urlString
        self.sortOrder = sortOrder
    }

    var resolvedURL: URL? {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmedURL),
              let scheme = components.scheme,
              scheme.isEmpty == false,
              components.host?.isEmpty == false || scheme == "file",
              let url = URL(string: trimmedURL) else {
            return nil
        }

        return url
    }

    var hasValidURL: Bool {
        resolvedURL != nil
    }
}

@Model
final class ProjectEvent {
    var title: String
    var notes: String
    var eventDate: Date
    var sortOrder: Int
    var project: Project?

    init(title: String, notes: String = "", eventDate: Date = .now, sortOrder: Int) {
        self.title = title
        self.notes = notes
        self.eventDate = eventDate
        self.sortOrder = sortOrder
    }
}

protocol SortOrdered: AnyObject {
    var sortOrder: Int { get set }
}

extension TemplateStep: SortOrdered {}
extension TemplateLink: SortOrdered {}
extension ProjectStep: SortOrdered {}
extension ProjectLink: SortOrdered {}
extension ProjectEvent: SortOrdered {}

extension Array where Element: SortOrdered & PersistentModel {
    func sortedBySortOrder() -> [Element] {
        sorted { first, second in
            if first.sortOrder == second.sortOrder {
                return first.persistentModelID.hashValue < second.persistentModelID.hashValue
            }

            return first.sortOrder < second.sortOrder
        }
    }

    var nextSortOrder: Int {
        (map(\.sortOrder).max() ?? -1) + 1
    }
}

extension MutableCollection where Element: SortOrdered {
    mutating func renumberSortOrder() {
        for index in indices {
            self[index].sortOrder = distance(from: startIndex, to: index)
        }
    }
}
