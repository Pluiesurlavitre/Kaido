//
//  geeTests.swift
//  geeTests
//
//  Created by Pluie on 23/04/2026.
//

import Foundation
import SwiftData
import Testing
@testable import gee

struct GeeTests {
    @Test("Creating a project snapshots ordered template content")
    func projectCreationSnapshotsTemplate() throws {
        let template = ProjectTemplate(name: "Client Launch")
        template.steps = [
            TemplateStep(name: "Second", sortOrder: 1),
            TemplateStep(name: "First", sortOrder: 0),
        ]
        template.links = [
            TemplateLink(name: "Assets", sortOrder: 1),
            TemplateLink(name: "Brief", sortOrder: 0),
        ]

        let project = Project(name: "Acme", template: template)

        #expect(project.templateName == "Client Launch")
        #expect(project.isArchived == false)
        #expect(project.isOngoing == false)
        #expect(project.orderedSteps.map(\.title) == ["First", "Second"])
        #expect(project.orderedLinks.map(\.name) == ["Brief", "Assets"])

        template.name = "Changed Template"
        template.steps[0].name = "Changed Step"
        template.links.append(TemplateLink(name: "Later Link", sortOrder: 2))

        #expect(project.templateName == "Client Launch")
        #expect(project.orderedSteps.map(\.title) == ["First", "Second"])
        #expect(project.orderedLinks.map(\.name) == ["Brief", "Assets"])
    }

    @Test("Progress counts planned or done steps and valid link URLs equally")
    func progressCalculation() {
        let project = Project(name: "Acme", templateName: "Manual")
        project.steps = [
            ProjectStep(title: "Todo", sortOrder: 0, status: .todo),
            ProjectStep(title: "Planned", sortOrder: 1, status: .planned),
            ProjectStep(title: "Done", sortOrder: 2, status: .done),
        ]
        project.links = [
            ProjectLink(name: "Brief", urlString: "https://example.com/brief", sortOrder: 0),
            ProjectLink(name: "Missing", sortOrder: 1),
        ]

        #expect(project.totalProgressItems == 5)
        #expect(project.completedProgressItems == 3)
        #expect(project.progress == 0.6)
    }

    @Test("Step status and date are independent")
    func statusAndDateAreIndependent() {
        let step = ProjectStep(title: "Book room", sortOrder: 0)
        let scheduledDate = Date(timeIntervalSince1970: 1_800_000_000)

        step.scheduledDate = scheduledDate
        #expect(step.status == .todo)
        #expect(step.isProgressComplete == false)

        step.status = .planned
        step.scheduledDate = nil
        #expect(step.status == .planned)
        #expect(step.isProgressComplete)
    }

    @Test("Sort order persists through SwiftData")
    func sortOrderPersists() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let template = ProjectTemplate(name: "Launch")
        template.steps = [
            TemplateStep(name: "Third", sortOrder: 2),
            TemplateStep(name: "First", sortOrder: 0),
            TemplateStep(name: "Second", sortOrder: 1),
        ]

        context.insert(template)
        try context.save()

        let descriptor = FetchDescriptor<ProjectTemplate>()
        let fetchedTemplate = try #require(try context.fetch(descriptor).first)

        #expect(fetchedTemplate.orderedSteps.map(\.name) == ["First", "Second", "Third"])
    }

    @Test("Link URLs require a scheme and destination")
    func linkURLValidation() {
        #expect(ProjectLink(name: "Good", urlString: "https://example.com", sortOrder: 0).hasValidURL)
        #expect(ProjectLink(name: "File", urlString: "file:///tmp/example.txt", sortOrder: 0).hasValidURL)
        #expect(ProjectLink(name: "Missing scheme", urlString: "example.com", sortOrder: 0).hasValidURL == false)
        #expect(ProjectLink(name: "Blank", urlString: "   ", sortOrder: 0).hasValidURL == false)
    }

    @Test("Incomplete projects warn as the start date approaches")
    @MainActor
    func projectScheduleWarningLevels() throws {
        let calendar = Calendar(identifier: .gregorian)
        let referenceDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 23)))

        let project = Project(name: "Acme", templateName: "Manual")
        project.steps = [ProjectStep(title: "Book room", sortOrder: 0, status: .todo)]

        project.startDate = referenceDate.addingTimeInterval(16 * 24 * 60 * 60)
        #expect(project.scheduleWarningLevel(relativeTo: referenceDate, calendar: calendar) == nil)

        project.startDate = referenceDate.addingTimeInterval(15 * 24 * 60 * 60)
        let warning = try #require(project.scheduleWarning(relativeTo: referenceDate, calendar: calendar))
        #expect(warning.level == .warning)
        #expect(warning.daysUntilStart == 15)

        project.startDate = referenceDate.addingTimeInterval(7 * 24 * 60 * 60)
        let criticalWarning = try #require(project.scheduleWarning(relativeTo: referenceDate, calendar: calendar))
        #expect(criticalWarning.level == .critical)
        #expect(criticalWarning.daysUntilStart == 7)

        project.steps[0].status = .done
        #expect(project.scheduleWarningLevel(relativeTo: referenceDate, calendar: calendar) == nil)
    }

    @Test("Archived projects track archive state and suppress schedule warnings")
    @MainActor
    func archivedProjectsSuppressWarnings() throws {
        let calendar = Calendar(identifier: .gregorian)
        let referenceDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 23)))
        let project = Project(
            name: "Archived",
            startDate: referenceDate.addingTimeInterval(7 * 24 * 60 * 60),
            templateName: "Manual",
            archivedAt: referenceDate
        )
        project.steps = [ProjectStep(title: "Still todo", sortOrder: 0, status: .todo)]

        #expect(project.isArchived)
        #expect(project.scheduleWarning(relativeTo: referenceDate, calendar: calendar) == nil)

        project.archivedAt = nil
        #expect(project.isArchived == false)
        #expect(project.scheduleWarningLevel(relativeTo: referenceDate, calendar: calendar) == .critical)
    }

    @Test("Ongoing projects track state, suppress warnings, and sort timeline events")
    @MainActor
    func ongoingProjectsUseTimelineEvents() throws {
        let calendar = Calendar(identifier: .gregorian)
        let referenceDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 23)))
        let project = Project(
            name: "Ongoing",
            startDate: referenceDate.addingTimeInterval(7 * 24 * 60 * 60),
            templateName: "Manual",
            ongoingStartedAt: referenceDate
        )
        project.steps = [ProjectStep(title: "Still todo", sortOrder: 0, status: .todo)]
        project.events = [
            ProjectEvent(title: "Older", eventDate: referenceDate.addingTimeInterval(-24 * 60 * 60), sortOrder: 0),
            ProjectEvent(title: "Latest", eventDate: referenceDate, sortOrder: 1),
        ]

        #expect(project.isOngoing)
        #expect(project.scheduleWarning(relativeTo: referenceDate, calendar: calendar) == nil)
        #expect(project.orderedEvents.map(\.title) == ["Latest", "Older"])

        project.ongoingStartedAt = nil
        #expect(project.isOngoing == false)
        #expect(project.scheduleWarningLevel(relativeTo: referenceDate, calendar: calendar) == .critical)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: AppModelSchema.schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: AppModelSchema.schema, configurations: [configuration])
    }
}
