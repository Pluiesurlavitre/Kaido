import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name) private var projects: [Project]
    @Query(sort: \ProjectFolder.name) private var folders: [ProjectFolder]
    @Query(sort: \ProjectTemplate.name) private var templates: [ProjectTemplate]

    @State private var selection: SidebarSelection?
    @State private var presentedSheet: PresentedSheet?
    @State private var expandedPreparationFolderIDs: Set<PersistentIdentifier> = []
    @State private var expandedOngoingFolderIDs: Set<PersistentIdentifier> = []
    @State private var isArchivedProjectsExpanded = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Projects") {
                    ProjectFolderedSidebarList(
                        folders: folders,
                        projects: activeProjects,
                        expandedFolderIDs: $expandedPreparationFolderIDs,
                        selection: $selection,
                        onDelete: deleteProjects
                    )
                }

                if ongoingProjects.isEmpty == false {
                    Section("Ongoing projects") {
                        ProjectFolderedSidebarList(
                            folders: folders,
                            projects: ongoingProjects,
                            expandedFolderIDs: $expandedOngoingFolderIDs,
                            selection: $selection,
                            onDelete: deleteProjects
                        )
                    }
                }

                if archivedProjects.isEmpty == false {
                    DisclosureGroup(isExpanded: $isArchivedProjectsExpanded) {
                        ForEach(archivedProjects) { project in
                            ProjectSidebarRow(project: project)
                                .tag(SidebarSelection.project(project.persistentModelID))
                        }
                        .onDelete(perform: deleteArchivedProjects)
                    } label: {
                        HStack {
                            Label("Archived", systemImage: "archivebox")
                            Spacer()
                            Text("\(archivedProjects.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Folders") {
                    ForEach(folders) { folder in
                        Label(folder.name, systemImage: "folder")
                            .tag(SidebarSelection.folder(folder.persistentModelID))
                    }
                    .onDelete(perform: deleteFolders)
                }

                Section("Templates") {
                    ForEach(templates) { template in
                        Label(template.name, systemImage: "doc.text")
                            .tag(SidebarSelection.template(template.persistentModelID))
                    }
                    .onDelete(perform: deleteTemplates)
                }
            }
            .navigationTitle("Preparation")
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
            .toolbar {
                ToolbarItemGroup {
                    Button("New Project", systemImage: "plus") {
                        presentedSheet = .newProject
                    }
                    .disabled(templates.isEmpty)

                    Button("New Folder", systemImage: "folder.badge.plus") {
                        presentedSheet = .newFolder
                    }

                    Button("New Template", systemImage: "doc.badge.plus") {
                        presentedSheet = .newTemplate
                    }
                }
            }
        } detail: {
            detailView
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .newProject:
                NewProjectSheet(templates: templates, folders: folders) { project in
                    modelContext.insert(project)
                    selection = .project(project.persistentModelID)
                }
            case .newTemplate:
                NewTemplateSheet { template in
                    modelContext.insert(template)
                    selection = .template(template.persistentModelID)
                }
            case .newFolder:
                NewFolderSheet { folder in
                    modelContext.insert(folder)
                    selection = .folder(folder.persistentModelID)
                }
            }
        }
    }

    private var activeProjects: [Project] {
        projects.filter { $0.isArchived == false && $0.isOngoing == false }
    }

    private var ongoingProjects: [Project] {
        projects.filter { $0.isArchived == false && $0.isOngoing }
    }

    private var archivedProjects: [Project] {
        projects.filter(\.isArchived)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .project(let id):
            if let project = projects.first(where: { $0.persistentModelID == id }) {
                ProjectDetailView(project: project, folders: folders)
            } else {
                EmptyStateView(
                    title: "Project Missing",
                    systemImage: "questionmark.folder",
                    description: "Select an existing project or create a new one."
                )
            }
        case .template(let id):
            if let template = templates.first(where: { $0.persistentModelID == id }) {
                TemplateDetailView(template: template)
            } else {
                EmptyStateView(
                    title: "Template Missing",
                    systemImage: "questionmark.doc",
                    description: "Select an existing template or create a new one."
                )
            }
        case .folder(let id):
            if let folder = folders.first(where: { $0.persistentModelID == id }) {
                FolderDetailView(
                    folder: folder,
                    projects: projects,
                    onSelectProject: { project in
                        selection = .project(project.persistentModelID)
                    },
                    onDelete: {
                        deleteFolder(folder)
                    }
                )
            } else {
                EmptyStateView(
                    title: "Folder Missing",
                    systemImage: "questionmark.folder",
                    description: "Select an existing folder or create a new one."
                )
            }
        case nil:
            EmptyStateView(
                title: "Choose a Project or Template",
                systemImage: "checklist",
                description: templates.isEmpty
                    ? "Create a template first, then use it to prepare projects."
                    : "Select an item from the sidebar to start editing."
            )
        }
    }

    private func deleteArchivedProjects(offsets: IndexSet) {
        deleteProjects(offsets: offsets, from: archivedProjects)
    }

    private func deleteProjects(offsets: IndexSet, from projectList: [Project]) {
        withAnimation {
            for index in offsets {
                let project = projectList[index]
                if selection == .project(project.persistentModelID) {
                    selection = nil
                }
                modelContext.delete(project)
            }
        }
    }

    private func deleteFolders(offsets: IndexSet) {
        let foldersToDelete = offsets.map { folders[$0] }

        withAnimation {
            for folder in foldersToDelete {
                deleteFolder(folder)
            }
        }
    }

    private func deleteFolder(_ folder: ProjectFolder) {
        let folderID = folder.persistentModelID

        if selection == .folder(folderID) {
            selection = nil
        }

        for project in projects where project.folder?.persistentModelID == folderID {
            project.folder = nil
        }

        modelContext.delete(folder)
    }

    private func deleteTemplates(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let template = templates[index]
                if selection == .template(template.persistentModelID) {
                    selection = nil
                }
                modelContext.delete(template)
            }
        }
    }
}

private struct ProjectSidebarRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 6) {
            Label(project.name, systemImage: project.sidebarSystemImage)

            Spacer(minLength: 4)

            if let warning = project.scheduleWarning() {
                ProjectScheduleWarningIcon(warning: warning)
            }
        }
    }
}

private extension Project {
    var sidebarSystemImage: String {
        if isArchived {
            return "archivebox"
        }

        if isOngoing {
            return "play.circle"
        }

        return "folder"
    }
}

private struct ProjectScheduleWarningIcon: View {
    let warning: ProjectScheduleWarning

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(warning.level.tint)
            .accessibilityLabel(warning.level.accessibilityLabel)
            .help(warning.helpText)
    }
}

private extension ProjectScheduleWarningLevel {
    var tint: Color {
        switch self {
        case .warning:
            .orange
        case .critical:
            .red
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .warning:
            "Project preparation warning"
        case .critical:
            "Project preparation critical warning"
        }
    }

}

private extension ProjectScheduleWarning {
    var helpText: String {
        switch daysUntilStart {
        case Int.min ..< 0:
            "This project started \(abs(daysUntilStart)) \(abs(daysUntilStart) == 1 ? "day" : "days") ago."
        case 0:
            "This project starts today."
        case 1:
            "This project starts in 1 day."
        default:
            "This project starts in \(daysUntilStart) days."
        }
    }
}


private struct ProjectFolderedSidebarList: View {
    let folders: [ProjectFolder]
    let projects: [Project]
    @Binding var expandedFolderIDs: Set<PersistentIdentifier>
    @Binding var selection: SidebarSelection?
    let onDelete: (_ offsets: IndexSet, _ projects: [Project]) -> Void

    var body: some View {
        ForEach(unfiledProjects) { project in
            ProjectSidebarRow(project: project)
                .tag(SidebarSelection.project(project.persistentModelID))
        }
        .onDelete { offsets in
            onDelete(offsets, unfiledProjects)
        }

        ForEach(visibleFolders) { folder in
            let folderProjects = projects(in: folder)

            DisclosureGroup(isExpanded: expandedBinding(for: folder)) {
                ForEach(folderProjects) { project in
                    ProjectSidebarRow(project: project)
                        .tag(SidebarSelection.project(project.persistentModelID))
                }
                .onDelete { offsets in
                    onDelete(offsets, folderProjects)
                }
            } label: {
                HStack {
                    Label(folder.name, systemImage: "folder")
                    Spacer()
                    Text("\(folderProjects.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var unfiledProjects: [Project] {
        projects.filter { $0.folder == nil }
    }

    private var visibleFolders: [ProjectFolder] {
        folders.filter { folder in
            projects.contains { $0.folder?.persistentModelID == folder.persistentModelID }
        }
    }

    private func projects(in folder: ProjectFolder) -> [Project] {
        projects.filter { $0.folder?.persistentModelID == folder.persistentModelID }
    }

    private func expandedBinding(for folder: ProjectFolder) -> Binding<Bool> {
        Binding(
            get: { expandedFolderIDs.contains(folder.persistentModelID) },
            set: { isExpanded in
                if isExpanded {
                    expandedFolderIDs.insert(folder.persistentModelID)
                } else {
                    expandedFolderIDs.remove(folder.persistentModelID)
                }
            }
        )
    }
}

private enum SidebarSelection: Hashable {
    case project(PersistentIdentifier)
    case folder(PersistentIdentifier)
    case template(PersistentIdentifier)
}

private enum PresentedSheet: Identifiable {
    case newProject
    case newTemplate
    case newFolder

    var id: String {
        switch self {
        case .newProject:
            "new-project"
        case .newTemplate:
            "new-template"
        case .newFolder:
            "new-folder"
        }
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


private struct FolderDetailView: View {
    @Bindable var folder: ProjectFolder
    let projects: [Project]
    let onSelectProject: (Project) -> Void
    let onDelete: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        Form {
            Section("Folder") {
                TextField("Folder name", text: $folder.name)

                LabeledContent("Projects", value: "\(folderProjects.count)")
            }

            Section("Assigned Projects") {
                if folderProjects.isEmpty {
                    Text("No projects in this folder.")
                        .foregroundStyle(.secondary)
                }

                ForEach(folderProjects) { project in
                    FolderProjectRow(
                        project: project,
                        onSelect: { onSelectProject(project) },
                        onRemove: { project.folder = nil }
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(folderTitle)
        .toolbar {
            ToolbarItem {
                Button("Delete Folder", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        }
        .confirmationDialog(
            "Delete \(folderTitle)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Projects in this folder will stay in your project list.")
        }
    }

    private var folderTitle: String {
        let trimmedName = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Untitled Folder" : trimmedName
    }

    private var folderProjects: [Project] {
        projects
            .filter { $0.folder?.persistentModelID == folder.persistentModelID }
            .sorted { first, second in
                if first.folderStatusTitle == second.folderStatusTitle {
                    return first.name.localizedStandardCompare(second.name) == .orderedAscending
                }

                return first.folderStatusSortOrder < second.folderStatusSortOrder
            }
    }
}

private struct FolderProjectRow: View {
    let project: Project
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                Label(project.name, systemImage: project.sidebarSystemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Text(project.folderStatusTitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Remove from Folder", systemImage: "xmark.circle", action: onRemove)
                .labelStyle(.iconOnly)
                .help("Remove from folder")
        }
    }
}

private extension Project {
    var folderStatusTitle: String {
        if isArchived {
            return "Archived"
        }

        if isOngoing {
            return "Ongoing"
        }

        return "Preparation"
    }

    var folderStatusSortOrder: Int {
        if isArchived {
            return 2
        }

        if isOngoing {
            return 1
        }

        return 0
    }
}


private struct NewFolderSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    let onCreate: (ProjectFolder) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder name", text: $name)
            }
            .formStyle(.grouped)
            .frame(minWidth: 360)
            .navigationTitle("New Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createFolder()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createFolder() {
        onCreate(ProjectFolder(name: trimmedName))
        dismiss()
    }
}

private struct NewTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    let onCreate: (ProjectTemplate) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Template name", text: $name)
            }
            .formStyle(.grouped)
            .frame(minWidth: 360)
            .navigationTitle("New Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createTemplate()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createTemplate() {
        onCreate(ProjectTemplate(name: trimmedName))
        dismiss()
    }
}

private struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss

    let templates: [ProjectTemplate]
    let folders: [ProjectFolder]
    let onCreate: (Project) -> Void

    @State private var name = ""
    @State private var includesStartDate = false
    @State private var startDate = Date()
    @State private var selectedTemplateID: PersistentIdentifier?
    @State private var selectedFolderID: PersistentIdentifier?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Project name", text: $name)

                Toggle("Set start date", isOn: $includesStartDate)

                if includesStartDate {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                }

                Picker("Template", selection: $selectedTemplateID) {
                    ForEach(templates) { template in
                        Text(template.name)
                            .tag(Optional(template.persistentModelID))
                    }
                }

                Picker("Folder", selection: $selectedFolderID) {
                    Text("No folder")
                        .tag(Optional<PersistentIdentifier>.none)

                    ForEach(folders) { folder in
                        Text(folder.name)
                            .tag(Optional(folder.persistentModelID))
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 420)
            .navigationTitle("New Project")
            .onAppear {
                selectedTemplateID = selectedTemplateID ?? templates.first?.persistentModelID
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createProject()
                    }
                    .disabled(trimmedName.isEmpty || selectedTemplate == nil)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedTemplate: ProjectTemplate? {
        guard let selectedTemplateID else {
            return nil
        }

        return templates.first { $0.persistentModelID == selectedTemplateID }
    }

    private var selectedFolder: ProjectFolder? {
        guard let selectedFolderID else {
            return nil
        }

        return folders.first { $0.persistentModelID == selectedFolderID }
    }

    private func createProject() {
        guard let selectedTemplate else {
            return
        }

        let project = Project(
            name: trimmedName,
            startDate: includesStartDate ? startDate : nil,
            template: selectedTemplate
        )
        project.folder = selectedFolder
        onCreate(project)
        dismiss()
    }
}

private struct TemplateDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var template: ProjectTemplate

    var body: some View {
        Form {
            Section("Template") {
                TextField("Name", text: $template.name)
            }

            Section("Steps") {
                OrderedTemplateStepList(
                    template: template,
                    onAdd: addStep,
                    onDelete: deleteStep
                )
            }

            Section("Link Names") {
                OrderedTemplateLinkList(
                    template: template,
                    onAdd: addLink,
                    onDelete: deleteLink
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle(template.name.isEmpty ? "Untitled Template" : template.name)
    }

    private func addStep() {
        let step = TemplateStep(name: "New step", sortOrder: template.steps.nextSortOrder)
        step.template = template
        modelContext.insert(step)
        template.steps.append(step)
    }

    private func deleteStep(_ step: TemplateStep) {
        modelContext.delete(step)
        renumber(template.orderedSteps.filter { $0.persistentModelID != step.persistentModelID })
    }

    private func addLink() {
        let link = TemplateLink(name: "New link", sortOrder: template.links.nextSortOrder)
        link.template = template
        modelContext.insert(link)
        template.links.append(link)
    }

    private func deleteLink(_ link: TemplateLink) {
        modelContext.delete(link)
        renumber(template.orderedLinks.filter { $0.persistentModelID != link.persistentModelID })
    }

}

private struct OrderedTemplateStepList: View {
    @Bindable var template: ProjectTemplate
    @State private var draggedStepID: PersistentIdentifier?

    let onAdd: () -> Void
    let onDelete: (TemplateStep) -> Void

    var body: some View {
        let steps = template.orderedSteps

        if steps.isEmpty {
            Text("No steps yet.")
                .foregroundStyle(.secondary)
        }

        ForEach(steps, id: \.persistentModelID) { step in
            TemplateStepRow(
                step: step,
                onDelete: { onDelete(step) }
            )
            .reorderable(
                item: step,
                items: steps,
                draggedItemID: $draggedStepID,
                isDragging: draggedStepID == step.persistentModelID
            )
        }

        Button("Add Step", systemImage: "plus", action: onAdd)
    }
}

private struct OrderedTemplateLinkList: View {
    @Bindable var template: ProjectTemplate
    @State private var draggedLinkID: PersistentIdentifier?

    let onAdd: () -> Void
    let onDelete: (TemplateLink) -> Void

    var body: some View {
        let links = template.orderedLinks

        if links.isEmpty {
            Text("No link names yet.")
                .foregroundStyle(.secondary)
        }

        ForEach(links, id: \.persistentModelID) { link in
            TemplateLinkRow(
                link: link,
                onDelete: { onDelete(link) }
            )
            .reorderable(
                item: link,
                items: links,
                draggedItemID: $draggedLinkID,
                isDragging: draggedLinkID == link.persistentModelID
            )
        }

        Button("Add Link Name", systemImage: "plus", action: onAdd)
    }
}

private struct DragHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 22)
            .help("Drag to reorder")
            .accessibilityLabel("Drag to reorder")
    }
}

private struct ReorderableRowModifier<Item: SortOrdered & PersistentModel>: ViewModifier {
    let item: Item
    let items: [Item]
    @Binding var draggedItemID: PersistentIdentifier?
    let isDragging: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isDragging ? 0.45 : 1)
            .contentShape(.rect)
            .onDrag {
                draggedItemID = item.persistentModelID
                return NSItemProvider(object: String(describing: item.persistentModelID) as NSString)
            }
            .onDrop(
                of: [.plainText],
                delegate: ReorderDropDelegate(
                    targetItem: item,
                    items: items,
                    draggedItemID: $draggedItemID
                )
            )
    }
}

private struct ReorderDropDelegate<Item: SortOrdered & PersistentModel>: DropDelegate {
    let targetItem: Item
    let items: [Item]
    @Binding var draggedItemID: PersistentIdentifier?

    func dropEntered(info: DropInfo) {
        guard let draggedItemID,
              draggedItemID != targetItem.persistentModelID,
              let sourceIndex = items.firstIndex(where: { $0.persistentModelID == draggedItemID }),
              let targetIndex = items.firstIndex(where: { $0.persistentModelID == targetItem.persistentModelID }) else {
            return
        }

        var reorderedItems = items
        reorderedItems.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        )
        renumber(reorderedItems)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItemID = nil
        return true
    }
}

private extension View {
    func reorderable<Item: SortOrdered & PersistentModel>(
        item: Item,
        items: [Item],
        draggedItemID: Binding<PersistentIdentifier?>,
        isDragging: Bool
    ) -> some View {
        modifier(
            ReorderableRowModifier(
                item: item,
                items: items,
                draggedItemID: draggedItemID,
                isDragging: isDragging
            )
        )
    }
}

private struct ConfirmingDeleteButton: View {
    let itemName: String
    let onConfirm: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            isConfirmingDelete = true
        }
        .labelStyle(.iconOnly)
        .confirmationDialog(
            "Delete \(itemName)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete \(itemName)", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

private struct TemplateStepRow: View {
    @Bindable var step: TemplateStep

    let onDelete: () -> Void

    var body: some View {
        HStack {
            DragHandle()

            TextField("Step name", text: $step.name)

            Spacer()

            ConfirmingDeleteButton(itemName: "step", onConfirm: onDelete)
        }
    }
}

private struct TemplateLinkRow: View {
    @Bindable var link: TemplateLink

    let onDelete: () -> Void

    var body: some View {
        HStack {
            DragHandle()

            TextField("Link name", text: $link.name)

            Spacer()

            ConfirmingDeleteButton(itemName: "link", onConfirm: onDelete)
        }
    }
}

private struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project
    let folders: [ProjectFolder]

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Project name", text: $project.name)
                        .font(.title2)
                        .labelsHidden()
                        .textFieldStyle(.plain)

                    OptionalProjectDatePicker(title: "Start date", date: $project.startDate)

                    ProjectFolderPicker(folders: folders, selectedFolder: folderBinding)

                    ProjectHeaderLinkButtons(project: project)

                    if project.isOngoing == false {
                        ProjectProgressHeader(project: project)
                    }
                }
                .padding(.vertical, 4)
            }

            if project.isOngoing {
                Section("Timeline") {
                    OrderedProjectEventList(
                        project: project,
                        onAdd: addEvent,
                        onDelete: deleteEvent
                    )
                }
            } else {
                Section("Steps") {
                    OrderedProjectStepList(
                        project: project,
                        onAdd: addStep,
                        onDelete: deleteStep
                    )
                }
            }

            Section("Links") {
                OrderedProjectLinkList(
                    project: project,
                    onAdd: addLink,
                    onDelete: deleteLink
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle(project.name.isEmpty ? "Untitled Project" : project.name)
        .toolbar {
            ToolbarItemGroup {
                if project.isArchived == false {
                    Button(project.isOngoing ? "Move to Preparation" : "Move to Ongoing", systemImage: project.isOngoing ? "checklist" : "play.circle") {
                        project.ongoingStartedAt = project.isOngoing ? nil : .now
                    }
                }

                Button(project.isArchived ? "Unarchive Project" : "Archive Project", systemImage: project.isArchived ? "archivebox.fill" : "archivebox") {
                    if project.isArchived {
                        project.archivedAt = nil
                    } else {
                        project.archivedAt = .now
                    }
                }
            }
        }
    }

    private var folderBinding: Binding<ProjectFolder?> {
        Binding(
            get: { project.folder },
            set: { project.folder = $0 }
        )
    }

    private func addStep() {
        let step = ProjectStep(title: "New step", sortOrder: project.steps.nextSortOrder)
        step.project = project
        modelContext.insert(step)
        project.steps.append(step)
    }

    private func deleteStep(_ step: ProjectStep) {
        modelContext.delete(step)
        renumber(project.orderedSteps.filter { $0.persistentModelID != step.persistentModelID })
    }

    private func addLink() {
        let link = ProjectLink(name: "New link", sortOrder: project.links.nextSortOrder)
        link.project = project
        modelContext.insert(link)
        project.links.append(link)
    }

    private func deleteLink(_ link: ProjectLink) {
        modelContext.delete(link)
        renumber(project.orderedLinks.filter { $0.persistentModelID != link.persistentModelID })
    }

    private func addEvent(title: String, notes: String, eventDate: Date) {
        let event = ProjectEvent(
            title: title,
            notes: notes,
            eventDate: eventDate,
            sortOrder: project.events.nextSortOrder
        )
        event.project = project
        modelContext.insert(event)
        project.events.append(event)
    }

    private func deleteEvent(_ event: ProjectEvent) {
        modelContext.delete(event)
        renumber(project.orderedEvents.filter { $0.persistentModelID != event.persistentModelID })
    }

}


private struct ProjectFolderPicker: View {
    let folders: [ProjectFolder]
    @Binding var selectedFolder: ProjectFolder?

    var body: some View {
        Picker("Folder", selection: folderIDBinding) {
            Text("No folder")
                .tag(Optional<PersistentIdentifier>.none)

            ForEach(folders) { folder in
                Text(folder.name)
                    .tag(Optional(folder.persistentModelID))
            }
        }
    }

    private var folderIDBinding: Binding<PersistentIdentifier?> {
        Binding(
            get: { selectedFolder?.persistentModelID },
            set: { selectedFolderID in
                selectedFolder = folders.first { $0.persistentModelID == selectedFolderID }
            }
        )
    }
}

private struct ProjectHeaderLinkButtons: View {
    let project: Project

    var body: some View {
        let links = project.orderedLinks

        if links.isEmpty == false {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(links, id: \.persistentModelID) { link in
                        ProjectHeaderLinkButton(link: link)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }
}

private struct ProjectHeaderLinkButton: View {
    @Environment(\.openURL) private var openURL
    @Bindable var link: ProjectLink

    var body: some View {
        Button {
            guard let url = link.resolvedURL else {
                return
            }

            openURL(url)
        } label: {
            Label(title, systemImage: link.hasValidURL ? "link" : "exclamationmark.circle.fill")
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .tint(link.hasValidURL ? .accentColor : .red)
        .foregroundStyle(link.hasValidURL ? Color.primary : Color.red)
        .accessibilityHint(link.hasValidURL ? "Opens this link." : "Add a valid URL to make this link openable.")
    }

    private var title: String {
        let trimmedName = link.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Untitled link" : trimmedName
    }
}

private struct ProjectProgressHeader: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Preparation progress")
                Spacer()
                Text("\(project.completedProgressItems) of \(project.totalProgressItems)")
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: project.progress)

            Text("\(Int((project.progress * 100).rounded()))% complete")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OrderedProjectStepList: View {
    @Bindable var project: Project
    @State private var draggedStepID: PersistentIdentifier?

    let onAdd: () -> Void
    let onDelete: (ProjectStep) -> Void

    var body: some View {
        let steps = project.orderedSteps

        if steps.isEmpty {
            Text("No steps yet.")
                .foregroundStyle(.secondary)
        }

        ForEach(steps, id: \.persistentModelID) { step in
            ProjectStepRow(
                step: step,
                onDelete: { onDelete(step) }
            )
            .reorderable(
                item: step,
                items: steps,
                draggedItemID: $draggedStepID,
                isDragging: draggedStepID == step.persistentModelID
            )
        }

        Button("Add Step", systemImage: "plus", action: onAdd)
    }
}

private struct OrderedProjectLinkList: View {
    @Bindable var project: Project
    @State private var draggedLinkID: PersistentIdentifier?

    let onAdd: () -> Void
    let onDelete: (ProjectLink) -> Void

    var body: some View {
        let links = project.orderedLinks

        if links.isEmpty {
            Text("No links yet.")
                .foregroundStyle(.secondary)
        }

        ForEach(links, id: \.persistentModelID) { link in
            ProjectLinkRow(
                link: link,
                onDelete: { onDelete(link) }
            )
            .reorderable(
                item: link,
                items: links,
                draggedItemID: $draggedLinkID,
                isDragging: draggedLinkID == link.persistentModelID
            )
        }

        Button("Add Link", systemImage: "plus", action: onAdd)
    }
}

private struct OrderedProjectEventList: View {
    @Bindable var project: Project

    let onAdd: (_ title: String, _ notes: String, _ eventDate: Date) -> Void
    let onDelete: (ProjectEvent) -> Void

    var body: some View {
        let events = project.orderedEvents

        ProjectEventComposer(onAdd: onAdd)

        if events.isEmpty {
            Text("No events yet.")
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }

        ForEach(events, id: \.persistentModelID) { event in
            ProjectEventRow(
                event: event,
                onDelete: { onDelete(event) }
            )
        }
    }
}

private struct ProjectEventComposer: View {
    let onAdd: (_ title: String, _ notes: String, _ eventDate: Date) -> Void

    @State private var eventDate: Date = .now
    @State private var eventText = ""

    private let editorInset = EdgeInsets(top: 8, leading: 5, bottom: 8, trailing: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Event date", selection: $eventDate, displayedComponents: .date)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $eventText)
                    .frame(minHeight: 90)

                if eventText.isEmpty {
                    Text("Add a timeline event...")
                        .foregroundStyle(.secondary)
                        .padding(editorInset)
                        .allowsHitTesting(false)
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.tertiary, lineWidth: 1)
            }

            HStack {
                Spacer()

                Button("Add Event", systemImage: "plus") {
                    addEvent()
                }
                .disabled(trimmedEventText.isEmpty)
            }
        }
        .padding(.vertical, 6)
    }

    private var trimmedEventText: String {
        eventText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addEvent() {
        let title = trimmedEventText
        onAdd(title, "", eventDate)
        eventText = ""
        eventDate = .now
    }
}

private struct ProjectEventRow: View {
    let event: ProjectEvent

    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TimelineMarker()

            VStack(alignment: .leading, spacing: 4) {
                Text(event.eventDate, format: .dateTime.day().month().year())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(event.title)
                    .font(.body)
                    .textSelection(.enabled)

                if event.notes.isEmpty == false {
                    Text(event.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ConfirmingDeleteButton(itemName: "event", onConfirm: onDelete)
        }
        .padding(.vertical, 8)
    }
}

private struct TimelineMarker: View {
    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 9, height: 9)

            Rectangle()
                .fill(.tertiary)
                .frame(width: 1)
        }
        .frame(width: 14)
        .frame(minHeight: 54)
    }
}

private struct ProjectStepRow: View {
    @Bindable var step: ProjectStep

    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            DragHandle()

            StatusCheckbox(status: statusBinding)

            TextField("Step", text: $step.title)
                .labelsHidden()
                .textFieldStyle(.plain)

            Spacer(minLength: 12)

            OptionalProjectDatePicker(title: "Date", date: $step.scheduledDate)

            ConfirmingDeleteButton(itemName: "step", onConfirm: onDelete)
        }
        .padding(.vertical, 4)
    }

    private var statusBinding: Binding<ProjectStepStatus> {
        Binding(
            get: { step.status },
            set: { step.status = $0 }
        )
    }
}

private struct StatusCheckbox: View {
    @Binding var status: ProjectStepStatus

    var body: some View {
        Button {
            status = status.next
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    if status == .planned {
                        PlannedHalfFill()
                            .fill(status.fillStyle)
                            .frame(width: 17, height: 17)
                    } else {
                        Circle()
                            .fill(status.fillStyle)
                            .frame(width: 17, height: 17)
                    }

                    Circle()
                        .strokeBorder(status.strokeStyle, lineWidth: 1.8)
                        .frame(width: 17, height: 17)

                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(status.symbolStyle)
                        .opacity(status == .done ? 1 : 0)
                }

                StatusBadge(status: status)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step status")
        .accessibilityValue(status.title)
        .accessibilityHint("Cycles between todo, planned, and done.")
    }
}

private struct StatusBadge: View {
    let status: ProjectStepStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.badgeForegroundStyle)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.badgeBackgroundStyle, in: Capsule())
    }
}

private struct PlannedHalfFill: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: min(rect.width, rect.height) / 2,
                startAngle: .degrees(-90),
                endAngle: .degrees(90),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private extension ProjectStepStatus {
    var fillStyle: Color {
        switch self {
        case .todo:
            .clear
        case .planned:
            .orange
        case .done:
            .green
        }
    }

    var strokeStyle: Color {
        switch self {
        case .todo:
            .secondary
        case .planned:
            .orange
        case .done:
            .green
        }
    }

    var symbolStyle: Color {
        switch self {
        case .todo:
            .clear
        case .planned:
            .orange
        case .done:
            .white
        }
    }

    var badgeForegroundStyle: Color {
        switch self {
        case .todo:
            .secondary
        case .planned:
            .orange
        case .done:
            .green
        }
    }

    var badgeBackgroundStyle: Color {
        switch self {
        case .todo:
            .secondary.opacity(0.12)
        case .planned:
            .orange.opacity(0.14)
        case .done:
            .green.opacity(0.14)
        }
    }
}

private struct ProjectLinkRow: View {
    @Bindable var link: ProjectLink

    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            DragHandle()

            TextField("Link", text: $link.name)
                .labelsHidden()
                .textFieldStyle(.plain)
                .frame(minWidth: 120)

            TextField("URL", text: $link.urlString)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)

            Image(systemName: link.hasValidURL ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(link.hasValidURL ? .green : .secondary)
                .accessibilityLabel(link.hasValidURL ? "URL complete" : "URL missing")

            ConfirmingDeleteButton(itemName: "link", onConfirm: onDelete)
        }
        .padding(.vertical, 4)
    }
}

private struct OptionalProjectDatePicker: View {
    let title: String
    @Binding var date: Date?

    var body: some View {
        HStack {
            if date == nil {
                Button("Add \(title.lowercased())", systemImage: "calendar.badge.plus") {
                    date = .now
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Add \(title.lowercased())")
            } else {
                DatePicker(title, selection: dateBinding, displayedComponents: .date)
                    .labelsHidden()

                Button("Clear", systemImage: "xmark.circle") {
                    date = nil
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { date ?? .now },
            set: { date = $0 }
        )
    }
}

private func renumber<Item: SortOrdered>(_ items: [Item]) {
    for (index, item) in items.enumerated() {
        item.sortOrder = index
    }
}

#Preview {
    ContentView()
        .modelContainer(for: AppModelSchema.models, inMemory: true)
}
