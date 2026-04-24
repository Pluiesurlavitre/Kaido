# Kaido

Kaido is a macOS app for preparing repeatable projects before they start, then tracking them while they are ongoing.

The app is built around templates. A template defines the steps and links that a type of project usually needs. When you create a project from a template, Kaido copies that checklist into the project so it can be edited independently without changing the original template.

## What It Does

- Create reusable project templates with ordered preparation steps.
- Add expected link fields to templates, then fill those links in per project.
- Create projects from templates with optional start dates.
- Track preparation progress from completed steps and valid links.
- Warn when an incomplete project is approaching its start date.
- Organize projects into folders.
- Move projects from preparation into an ongoing state.
- Record dated timeline events for ongoing projects.
- Archive finished or inactive projects without deleting them.

## Project Flow

1. Create a template for a repeatable kind of project.
2. Add the steps and link names that project type usually needs.
3. Create a project from the template.
4. Assign the project to a folder if useful.
5. Work through the preparation checklist and fill in links.
6. Move the project to ongoing when preparation becomes active work.
7. Add timeline events while the project is ongoing.
8. Archive the project when it is finished.

## Technology

Kaido is a native macOS app built with SwiftUI and SwiftData.

## Development

Build the app with Xcode or from the command line:

```sh
xcodebuild -project kaido.xcodeproj -scheme kaido -sdk macosx build
```
