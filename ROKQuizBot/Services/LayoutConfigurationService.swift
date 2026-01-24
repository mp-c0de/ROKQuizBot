// LayoutConfigurationService.swift
// Service for managing quiz layout configurations
// Made by mpcode

import Foundation

final class LayoutConfigurationService {
    // MARK: - Properties

    /// All saved layouts
    private(set) var layouts: [QuizLayoutConfiguration] = []

    /// Currently active layout ID
    private(set) var activeLayoutID: UUID?

    private let layoutsFileURL: URL
    private let activeLayoutFileURL: URL

    /// Currently active layout (convenience property)
    var activeLayout: QuizLayoutConfiguration? {
        guard let id = activeLayoutID else { return nil }
        return layouts.first { $0.id == id }
    }

    // MARK: - Init

    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let appFolder = documentsPath.appendingPathComponent("ROKQuizBot", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        layoutsFileURL = appFolder.appendingPathComponent("quiz_layouts.json")
        activeLayoutFileURL = appFolder.appendingPathComponent("active_layout.json")

        loadLayouts()
        loadActiveLayoutID()

        print("[LayoutService] Loaded \(layouts.count) layouts, active: \(activeLayoutID?.uuidString.prefix(8) ?? "none")")
    }

    // MARK: - Load/Save Layouts

    private func loadLayouts() {
        guard FileManager.default.fileExists(atPath: layoutsFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: layoutsFileURL)
            layouts = try JSONDecoder().decode([QuizLayoutConfiguration].self, from: data)
        } catch {
            print("[LayoutService] Error loading layouts: \(error)")
        }
    }

    private func saveLayouts() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(layouts)
            try data.write(to: layoutsFileURL)
        } catch {
            print("[LayoutService] Error saving layouts: \(error)")
        }
    }

    private func loadActiveLayoutID() {
        guard FileManager.default.fileExists(atPath: activeLayoutFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: activeLayoutFileURL)
            activeLayoutID = try JSONDecoder().decode(UUID?.self, from: data)
        } catch {
            print("[LayoutService] Error loading active layout ID: \(error)")
        }
    }

    private func saveActiveLayoutID() {
        do {
            let data = try JSONEncoder().encode(activeLayoutID)
            try data.write(to: activeLayoutFileURL)
        } catch {
            print("[LayoutService] Error saving active layout ID: \(error)")
        }
    }

    // MARK: - CRUD Operations

    /// Adds a new layout and optionally sets it as active
    func addLayout(_ layout: QuizLayoutConfiguration, setActive: Bool = true) {
        layouts.append(layout)
        saveLayouts()

        if setActive {
            setActiveLayout(layout.id)
        }

        print("[LayoutService] Added layout: \(layout.name)")
    }

    /// Updates an existing layout
    func updateLayout(_ layout: QuizLayoutConfiguration) {
        guard let index = layouts.firstIndex(where: { $0.id == layout.id }) else {
            print("[LayoutService] Layout not found for update: \(layout.id)")
            return
        }

        var updatedLayout = layout
        updatedLayout.updatedAt = Date()
        layouts[index] = updatedLayout
        saveLayouts()

        print("[LayoutService] Updated layout: \(layout.name)")
    }

    /// Deletes a layout by ID
    func deleteLayout(_ id: UUID) {
        layouts.removeAll { $0.id == id }
        saveLayouts()

        // Clear active layout if it was deleted
        if activeLayoutID == id {
            activeLayoutID = nil
            saveActiveLayoutID()
        }

        print("[LayoutService] Deleted layout: \(id)")
    }

    /// Sets the active layout by ID
    func setActiveLayout(_ id: UUID?) {
        activeLayoutID = id
        saveActiveLayoutID()
        print("[LayoutService] Active layout set to: \(id?.uuidString.prefix(8) ?? "none")")
    }

    /// Clears the active layout
    func clearActiveLayout() {
        setActiveLayout(nil)
    }

    /// Gets a layout by ID
    func getLayout(_ id: UUID) -> QuizLayoutConfiguration? {
        return layouts.first { $0.id == id }
    }

    /// Creates a default layout if none exists and sets it as active
    func createDefaultLayoutIfNeeded() -> QuizLayoutConfiguration? {
        if layouts.isEmpty {
            let defaultLayout = QuizLayoutConfiguration.createDefault()
            addLayout(defaultLayout, setActive: true)
            return defaultLayout
        }
        return activeLayout
    }
}
