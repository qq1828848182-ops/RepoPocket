"""Always-visible native List with original soft-group decoration (no disclosure)."""
from pathlib import Path
ui = Path('RepoPocket/RepoPocketApp.swift').read_text()
style = Path('RepoPocket/WorkspaceSelectionUI.swift').read_text()
repositories = ui.split('struct RepositoriesView:', 1)[1].split('struct BrowserView:', 1)[0]
section = repositories.split('Section("我的仓库") {', 1)[1].split('.listStyle(.insetGrouped)', 1)[0]
for removed in ['DisclosureGroup', 'repositoriesExpanded', 'nativeRepositoryDisclosureRow', 'Text("仓库列表")']:
    assert removed not in ui + style
assert 'ForEach(repos)' in section and 'NavigationLink' in section
assert 'top: repo.id == repos.first?.id, bottom: repo.id == repos.last?.id' in section
assert section.count('.softGroupedRow(top: true, bottom: true)') == 2
assert '.listStyle(.insetGrouped)' in repositories and 'NavigationStack' in repositories
assert 'withAnimation' not in repositories and '.animation(' not in repositories
assert 'VStack {' not in section and 'ScrollView {' not in section and '.id(' not in section
assert 'repos = []' not in section and 'refresh()' not in section
assert 'let radius: CGFloat = 22' in style and 'cornerRadius: radius, style: .continuous' in style
assert 'listRowSeparator(.hidden)' in style and '.overlay(alignment: .bottom)' in style
assert '.frame(height: 0.5)' in style and '.fill(Color(uiColor: .separator))' in style
print('PASS always-visible repository List, original first/last 22pt continuous corners, full-width dividers; actual device appearance unmeasured')
