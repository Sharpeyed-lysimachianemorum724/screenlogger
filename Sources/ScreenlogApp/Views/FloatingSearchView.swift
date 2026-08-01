import AppKit
import ScreenlogCore
import SwiftUI

/// Screenlogger Library: fast query, progressive refinements, and visual results.
struct FloatingSearchView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var focusResultsRequest = 0
    @State private var selectedSuggestionID: String?
    @State private var presentedSearchText = ""
    @State private var committedOperatorValues: [SearchOperatorKind: String] = [:]
    @State private var lastRawQueryWrittenByEditor: String?
    @State private var suppressAutocompleteUntilEditorChanges = false
    @State private var assistantHandoffRequest: AssistantHandoffSheetRequest?
    @State private var assistantHandoffValidationMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .zIndex(3)

            Divider()

            if let issue = model.captureIssue {
                SLCaptureIssueBanner(issue: issue, context: "library")
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            SearchPane(focusRequest: focusResultsRequest)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.bottom, 12)
        .frame(
            minWidth: SLDesign.workspaceMinimumWidth,
            minHeight: SLDesign.workspaceMinimumHeight
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.showSearchOperatorMenu = false
            synchronizePresentationFromRawQuery(model.searchQuery)
            searchFocused = true
            model.refreshIntegrationSettings(automatic: true)
        }
        .onChange(of: model.shellFocusSearch) { _, focus in
            if focus {
                searchFocused = true
            } else if model.showSearchDatePicker || !model.shellSearchMode {
                searchFocused = false
            }
        }
        .onChange(of: model.showSearchOperatorMenu) { _, isVisible in
            if !isVisible { selectedSuggestionID = nil }
        }
        .onChange(of: model.showSearchDatePicker) { wasVisible, isVisible in
            if wasVisible, !isVisible, model.shellSearchMode {
                restoreSearchFocus(reopeningAutocomplete: false)
            }
        }
        .onChange(of: model.searchAutocompleteRows.map(\.id)) { _, rowIDs in
            guard let selectedSuggestionID else { return }
            if !rowIDs.contains(selectedSuggestionID) {
                self.selectedSuggestionID = nil
            }
        }
        .onExitCommand {
            handleExitCommand()
        }
        .sheet(item: $assistantHandoffRequest) { request in
            AssistantHandoffSheet(request: request)
                .environmentObject(model)
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchInput

            if let assistantHandoffValidationMessage {
                Label(assistantHandoffValidationMessage, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("library.assistant.validation")
            }

            if hasPresentedOperatorChips {
                SearchActiveOperatorChips(
                    values: committedOperatorValues,
                    compact: true,
                    excluding: draftedOperatorKinds,
                    onRemove: removeCommittedOperator
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("library.search.operators")
                .padding(.horizontal, 2)
            }

            if model.searchSessionScoped {
                sessionScopeRow
                    .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: 680)
        .popover(isPresented: searchDatePickerPresentation, arrowEdge: .top) {
            SearchDatePickerPopover()
                .environmentObject(model)
        }
    }

    private var searchInput: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField(
                    searchPlaceholder,
                    text: presentedSearchBinding
                )
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .disabled(model.libraryStartupIssue != nil)
                .accessibilityLabel("Search screen history")
                .accessibilityHint("Use the arrow keys or Tab to move through suggestions")
                .accessibilityIdentifier("library.search.field")
                .onKeyPress(phases: .down) { keyPress in
                    if let binding = model.keyboardShortcutBinding(for: .askAssistant),
                        binding.matches(keyPress)
                    {
                        presentAssistantHandoff()
                        return .handled
                    }
                    guard keyPress.key == .return else { return .ignored }
                    let shortcutModifiers = keyPress.modifiers.intersection([
                        .command, .control, .option, .shift,
                    ])
                    guard shortcutModifiers.isEmpty else { return .ignored }
                    if applySelectedAutocompleteRow() {
                        return .handled
                    }
                    commitRecognizedOperatorDrafts()
                    model.showSearchOperatorMenu = false
                    model.startLibrarySearch()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    if moveAutocompleteSelection(by: 1) {
                        return .handled
                    }
                    guard !model.filteredSearchResults.isEmpty else { return .ignored }
                    searchFocused = false
                    focusResultsRequest &+= 1
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveAutocompleteSelection(by: -1) ? .handled : .ignored
                }
                .onKeyPress(.tab, phases: .down) { keyPress in
                    moveAutocompleteSelectionForTab(
                        backward: keyPress.modifiers.contains(.shift)
                    ) ? .handled : .ignored
                }
                .onKeyPress(.delete) {
                    guard presentedSearchText.isEmpty,
                        let kind = SearchOperatorKind.allCases.reversed().first(where: {
                            committedOperatorValues[$0] != nil
                        })
                    else { return .ignored }
                    removeCommittedOperator(kind)
                    return .handled
                }
                .onChange(of: model.searchQuery) { _, query in
                    assistantHandoffValidationMessage = nil
                    let wasWrittenByEditor =
                        LibrarySearchQueryChangeRouting
                        .shouldScheduleDebouncedSearch(
                            changedQuery: query,
                            lastEditorWrittenQuery: lastRawQueryWrittenByEditor
                        )
                    synchronizePresentedText(afterRawQueryChangedTo: query)
                    guard wasWrittenByEditor else { return }
                    model.scheduleSearchDebounced(autocompleteInput: presentedSearchText)
                }
                .onChange(of: searchFocused) { _, focused in
                    model.shellFocusSearch = focused
                    if focused {
                        if suppressAutocompleteUntilEditorChanges {
                            model.showSearchOperatorMenu = false
                        } else {
                            model.refreshSearchAutocomplete(for: presentedSearchText)
                        }
                    } else {
                        commitRecognizedOperatorDrafts()
                        model.showSearchOperatorMenu = false
                    }
                }

                if !presentedSearchText.isEmpty {
                    Button(action: clearSearchTextAndRestoreFocus) {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear Search Text")
                    .accessibilityLabel("Clear Search")
                    .accessibilityHint(
                        "Keeps your application, website, date, time, and session filters"
                    )
                    .accessibilityIdentifier("library.search.clear")
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        Color(nsColor: .separatorColor).opacity(0.7),
                        lineWidth: 1
                    )
            }
            .overlay(alignment: .topLeading) {
                if model.showSearchOperatorMenu, !model.searchAutocompleteRows.isEmpty {
                    SearchAutocompleteMenu(
                        selectedRowID: $selectedSuggestionID,
                        onApply: applyAutocompleteRow
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: autocompleteMenuHeight, alignment: .top)
                    .offset(y: 38)
                    .accessibilitySortPriority(2)
                }
            }

            Button {
                presentAssistantHandoff()
            } label: {
                Label("Ask Assistant", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .fixedSize()
            .disabled(model.libraryStartupIssue != nil)
            .help(
                "Ask an Assistant (\(model.keyboardShortcutDisplayLabel(for: .askAssistant)))"
            )
            .accessibilityHint("Reviews the exact search context before opening an assistant")
            .accessibilityIdentifier("library.assistant.open")
        }
        .zIndex(3)
    }

    private var autocompleteMenuHeight: CGFloat {
        let rows = model.searchAutocompleteRows
        var sectionKinds = Set<String>()
        for row in rows {
            switch row {
            case .op: sectionKinds.insert("filters")
            case .site: sectionKinds.insert("websites")
            case .app: sectionKinds.insert("applications")
            case .dateValue, .pickDate: sectionKinds.insert("dates")
            }
        }
        let contentHeight = CGFloat(rows.count * 48 + sectionKinds.count * 24 + 10)
        return min(300, max(72, contentHeight))
    }

    private var searchPlaceholder: String {
        if model.libraryStartupIssue != nil {
            return "Library unavailable"
        }
        if !committedOperatorValues.isEmpty || model.searchSessionScoped {
            return "Add search terms..."
        }
        return "Search your screen history..."
    }

    private var searchDatePickerPresentation: Binding<Bool> {
        Binding(
            get: {
                model.showSearchDatePicker && model.searchDatePickerOrigin == .search
            },
            set: { isPresented in
                if !isPresented { model.showSearchDatePicker = false }
            }
        )
    }

    private var sessionScopeRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.fill")
                    .accessibilityHidden(true)
                Text("Current Session")
                    .fontWeight(.semibold)
                if let session = model.selectedSession {
                    Text(session.appLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(model.accentSwiftUIColor)
            .background(model.accentSwiftUIColor.opacity(0.12), in: Capsule(style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current Session")
            .accessibilityValue(sessionScopeAccessibilityValue)
            .accessibilityIdentifier("library.search.scope.session")

            Spacer(minLength: 4)

            Button {
                model.setSearchSessionScoped(false)
                searchFocused = true
                model.shellFocusSearch = true
            } label: {
                Label("Search All Library", systemImage: "books.vertical")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Remove the current-session limit and search your entire Library")
            .accessibilityHint("Removes the current-session search limit")
            .accessibilityIdentifier("library.search.scope.all-library")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.search.scope")
    }

    private var sessionScopeAccessibilityValue: String {
        guard let session = model.selectedSession else {
            return "Search limited to the Timeline session"
        }
        return "Search limited to the \(session.appLabel) session"
    }

    private func handleExitCommand() {
        if model.showSearchDatePicker {
            model.showSearchDatePicker = false
        } else if model.showSearchOperatorMenu {
            selectedSuggestionID = nil
            model.showSearchOperatorMenu = false
            restoreSearchFocus()
        } else {
            SearchWindowController.shared.hide()
        }
    }

    private func restoreSearchFocus(reopeningAutocomplete: Bool = true) {
        suppressAutocompleteUntilEditorChanges = !reopeningAutocomplete
        model.shellFocusSearch = false
        DispatchQueue.main.async {
            model.shellFocusSearch = true
        }
    }

    private func clearSearchTextAndRestoreFocus() {
        selectedSuggestionID = nil
        presentedSearchText = ""
        lastRawQueryWrittenByEditor = nil
        model.clearLibrarySearch(.text)
        DispatchQueue.main.async {
            searchFocused = true
            model.shellFocusSearch = true
        }
    }

    private func presentAssistantHandoff() {
        assistantHandoffValidationMessage = nil
        commitRecognizedOperatorDrafts()

        guard !model.searchQueryNeedsMoreInput else {
            assistantHandoffValidationMessage =
                "Finish the search word or filter before asking an assistant."
            return
        }

        let prompt: LibraryAssistantHandoffPrompt
        do {
            prompt = try model.buildLibraryAssistantHandoffPrompt()
        } catch {
            assistantHandoffValidationMessage =
                "Enter a search or add a filter before asking an assistant."
            return
        }

        let destinations = model.assistantHandoffDestinations()
        if destinations.isEmpty, model.integrationRefreshIsActive {
            assistantHandoffValidationMessage =
                "Checking Assistant Connections... Try again in a moment."
            return
        }

        selectedSuggestionID = nil
        model.showSearchOperatorMenu = false
        assistantHandoffRequest = AssistantHandoffSheetRequest(
            prompt: prompt,
            destinations: destinations,
            decision: model.assistantHandoffRoutingDecision(for: destinations)
        )
    }

    private func removeCommittedOperator(_ kind: SearchOperatorKind) {
        committedOperatorValues[kind] = nil
        writeComposedRawQuery()
        restoreSearchFocus(reopeningAutocomplete: false)
    }

    private func moveAutocompleteSelection(by delta: Int) -> Bool {
        let rows = model.searchAutocompleteRows
        guard model.showSearchOperatorMenu, !rows.isEmpty else { return false }

        let nextIndex: Int
        if let selectedSuggestionID,
            let current = rows.firstIndex(where: { $0.id == selectedSuggestionID })
        {
            // Down from the final suggestion continues into the current result
            // set. Returning false lets the field's Down Arrow handler perform
            // that focus handoff; Tab keeps its separate native traversal path.
            if delta > 0, current == rows.index(before: rows.endIndex) {
                return false
            }
            nextIndex = min(max(rows.startIndex, current + delta), rows.index(before: rows.endIndex))
        } else {
            nextIndex = delta < 0 ? rows.index(before: rows.endIndex) : rows.startIndex
        }
        selectedSuggestionID = rows[nextIndex].id
        return true
    }

    private func moveAutocompleteSelectionForTab(backward: Bool) -> Bool {
        let rows = model.searchAutocompleteRows
        guard model.showSearchOperatorMenu, !rows.isEmpty else { return false }

        if let selectedSuggestionID,
            let current = rows.firstIndex(where: { $0.id == selectedSuggestionID })
        {
            if backward {
                guard current > rows.startIndex else {
                    self.selectedSuggestionID = nil
                    return false
                }
                self.selectedSuggestionID = rows[rows.index(before: current)].id
            } else {
                let next = rows.index(after: current)
                guard next < rows.endIndex else {
                    self.selectedSuggestionID = nil
                    return false
                }
                self.selectedSuggestionID = rows[next].id
            }
        } else {
            guard !backward else { return false }
            selectedSuggestionID = rows[rows.startIndex].id
        }
        return true
    }

    private func applySelectedAutocompleteRow() -> Bool {
        guard model.showSearchOperatorMenu,
            let selectedSuggestionID,
            let row = model.searchAutocompleteRows.first(where: { $0.id == selectedSuggestionID })
        else { return false }
        applyAutocompleteRow(row)
        return true
    }

    private func applyAutocompleteRow(_ row: SearchAutocompleteRow) {
        selectedSuggestionID = nil

        switch row {
        case .op(let kind):
            presentedSearchText = SearchOperatorParser.insertOperator(
                kind,
                into: presentedSearchText
            )
            if kind == .date || kind == .before || kind == .since {
                model.searchDatePickerKind = kind
            }
            writeComposedRawQuery()
            model.enterShellSearch()
            model.refreshSearchAutocomplete(for: presentedSearchText)
        case .app, .site, .dateValue:
            model.applyAutocompleteRow(row)
            synchronizePresentationFromRawQuery(model.searchQuery)
            model.refreshSearchAutocomplete(for: presentedSearchText)
        case .pickDate:
            model.applyAutocompleteRow(row)
        }

        if case .pickDate = row {
            searchFocused = false
            model.shellFocusSearch = false
        } else {
            DispatchQueue.main.async {
                searchFocused = true
                model.shellFocusSearch = true
            }
        }
    }

    private var presentedSearchBinding: Binding<String> {
        Binding(
            get: { presentedSearchText },
            set: { newValue in
                suppressAutocompleteUntilEditorChanges = false
                presentedSearchText = newValue
                writeComposedRawQuery()

                if newValue.last?.isWhitespace == true,
                    !draftedOperatorKinds.isEmpty,
                    hasBalancedQuotes(in: newValue)
                {
                    commitRecognizedOperatorDrafts()
                }
            }
        )
    }

    private var draftedOperatorKinds: [SearchOperatorKind] {
        SearchOperatorKind.allCases.filter { kind in
            presentedSearchText.range(
                of: #"(?i)\b\#(kind.rawValue):"#,
                options: .regularExpression
            ) != nil
        }
    }

    private var hasPresentedOperatorChips: Bool {
        SearchOperatorKind.allCases.contains { kind in
            committedOperatorValues[kind] != nil && !draftedOperatorKinds.contains(kind)
        }
    }

    private func composeRawQuery(from editorText: String) -> String {
        var operatorTokens: [String] = []

        for kind in SearchOperatorKind.allCases {
            guard !draftedOperatorKinds.contains(kind),
                let value = committedOperatorValues[kind]
            else { continue }
            operatorTokens.append(operatorToken(kind, value: value))
        }

        let operatorPrefix = operatorTokens.joined(separator: " ")
        guard !operatorPrefix.isEmpty else { return editorText }
        guard !editorText.isEmpty else { return operatorPrefix }
        return operatorPrefix + " " + editorText
    }

    private func operatorToken(_ kind: SearchOperatorKind, value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeValue = value.contains(where: \.isWhitespace) ? "\"\(value)\"" : value
        return kind.prefix + safeValue
    }

    private func hasBalancedQuotes(in text: String) -> Bool {
        text.reduce(into: 0) { count, character in
            if character == "\"" { count += 1 }
        }.isMultiple(of: 2)
    }

    private func writeComposedRawQuery() {
        let rawQuery = composeRawQuery(from: presentedSearchText)
        guard rawQuery != model.searchQuery else {
            lastRawQueryWrittenByEditor = nil
            return
        }
        lastRawQueryWrittenByEditor = rawQuery
        model.searchQuery = rawQuery
    }

    private func synchronizePresentedText(afterRawQueryChangedTo query: String) {
        if query == lastRawQueryWrittenByEditor {
            lastRawQueryWrittenByEditor = nil
            return
        }
        synchronizePresentationFromRawQuery(query)
    }

    private func synchronizePresentationFromRawQuery(_ rawQuery: String) {
        lastRawQueryWrittenByEditor = nil
        let recognizedValues = recognizedOperatorValues(
            from: SearchOperatorParser.parse(rawQuery)
        )
        committedOperatorValues = recognizedValues
        presentedSearchText = editorText(
            removing: recognizedValues,
            from: rawQuery
        )
    }

    private func commitRecognizedOperatorDrafts() {
        let recognizedValues = recognizedOperatorValues(
            from: SearchOperatorParser.parse(presentedSearchText)
        )
        guard !recognizedValues.isEmpty else {
            writeComposedRawQuery()
            return
        }

        for (kind, value) in recognizedValues {
            committedOperatorValues[kind] = value
        }
        presentedSearchText = editorText(
            removing: recognizedValues,
            from: presentedSearchText
        )
        writeComposedRawQuery()
    }

    private func recognizedOperatorValues(
        from parsed: ParsedSearchQuery
    ) -> [SearchOperatorKind: String] {
        var values: [SearchOperatorKind: String] = [:]

        if let value = parsed.rawApp ?? parsed.appFilter,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            values[.app] = value
        }
        if let value = parsed.rawSite ?? parsed.siteFilter,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            values[.site] = value
        }
        if let value = parsed.rawDate, parsed.dayStartMs != nil {
            values[.date] = value
        }
        if let value = parsed.rawBefore, parsed.beforeMs != nil {
            values[.before] = value
        }
        if let value = parsed.rawSince, parsed.sinceMs != nil {
            values[.since] = value
        }

        return values
    }

    private func editorText(
        removing recognizedValues: [SearchOperatorKind: String],
        from rawQuery: String
    ) -> String {
        var editorText = rawQuery
        for kind in SearchOperatorKind.allCases where recognizedValues[kind] != nil {
            editorText = SearchOperatorParser.removeOperator(kind, from: editorText)
        }
        return editorText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

/// Leading location marker hosted by the native Library window toolbar.
struct LibraryToolbarLocationView: View {
    var body: some View {
        Label("Library", systemImage: "books.vertical")
            .labelStyle(.titleAndIcon)
            .font(.headline)
            .foregroundStyle(.primary)
            .fixedSize()
            .accessibilityIdentifier("library.location")
    }
}

/// State-aware capture and navigation controls hosted by AppKit's toolbar.
struct LibraryToolbarActionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            SLCaptureStatusToolbarView(
                setupOrigin: .library,
                accessibilityIdentifier: "library.capture.status"
            )
            SLPrimaryNavigation(current: .library)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.chrome.toolbar-actions")
    }

}
