"""Stable two-section containers; no animated per-row corner deformation."""
from pathlib import Path
ui = Path('RepoPocket/RepoPocketApp.swift').read_text()
style = Path('RepoPocket/WorkspaceSelectionUI.swift').read_text()
sections = Path('RepoPocket/RepositorySections.swift').read_text()
home = ui.split('struct RepositoriesView:', 1)[1].split('struct BrowserView:', 1)[0]
settings = ui.split('struct SettingsView:', 1)[1]
assert 'case owned, starred' in sections
for title, symbol in [('我的仓库', 'folder'), ('已加星标', 'star')]:
    assert f'return "{title}"' in sections
    assert f'return "{symbol}"' in sections
    assert f'Label("{title}", systemImage: "{symbol}")' in settings
for removed in ['organizations', 'projects', 'person.3', 'square.grid.2x2']:
    assert removed not in sections + home + settings
assert home.count('RepositorySectionContainer(section:') == 2
assert 'expanded: $ownedExpanded' in home and 'expanded: $starredExpanded' in home
container = sections.split('struct RepositorySectionContainer', 1)[1].split('struct RepositoryCollectionView', 1)[0]
assert container.index('Image(systemName: section.systemImage)') < container.index('if expanded {')
assert container.index('Text(section.title)') < container.index('if expanded {')
assert 'RoundedRectangle(cornerRadius: 22, style: .continuous)' in container
assert 'Transaction(animation: nil)' in container
assert 'withTransaction(transaction) { expanded.toggle() }' in container
assert 'transaction.disablesAnimations = true' in container
assert 'transaction.animation = nil' in container
assert '.frame(minHeight: 52)' in container and 'VStack(spacing: 0)' in container
assert '.listRowInsets(EdgeInsets())' in container
assert '.listRowSeparator(.hidden)' in container
assert '.listRowBackground(Color.clear)' in container
assert '.secondarySystemGroupedBackground' in container
assert container.count('RoundedRectangle(') == 1
assert 'Divider().padding(.horizontal, 16)' in container
for removed in ['DisclosureGroup', 'withAnimation', '.animation(', '.transition(', 'SoftGroupShape', '.clipShape(', '.id(']:
    assert removed not in container
assert 'softGroupedRow' not in container
assert 'RepositoryCollectionView(api: api, section: .owned)' in home + settings
assert 'RepositoryCollectionView(api: api, section: .starred)' in home + settings
assert 'ForEach(repositories)' in sections and 'BrowserView(api: api' in sections
assert 'api.starredRepositories()' in sections
assert 'api.fork(repository.full_name)' in sections
assert 'allowsFullSwipe: false' in sections and 'if !isOwn(repository)' in sections
assert 'confirmationDialog("复刻到我的仓库？"' in sections
assert sections.count('guard generation == AccountStore.generation') == 2
assert 'TextField("仓库链接", text: $input)' in home
assert 'let radius: CGFloat = 22' in style
print('PASS two icons, navigation, fixed outer 22pt outline, persistent headers, no-animation toggles including Reduce Motion, guarded Fork; device appearance unverified')
