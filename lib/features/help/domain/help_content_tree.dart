import 'help_content_page.dart';

List<HelpContentPage> helpPagesInTreeOrder(Iterable<HelpContentPage> pages) {
  final pageByKey = <String, HelpContentPage>{};
  for (final page in pages) {
    if (page.key.trim().isEmpty) continue;
    pageByKey[page.key] = page;
  }

  final childrenByParentKey = <String, List<HelpContentPage>>{};
  final roots = <HelpContentPage>[];
  for (final page in pageByKey.values) {
    final parentKey = page.parentKey;
    if (parentKey == null ||
        parentKey == page.key ||
        !pageByKey.containsKey(parentKey)) {
      roots.add(page);
      continue;
    }
    childrenByParentKey.putIfAbsent(parentKey, () => []).add(page);
  }

  final ordered = <HelpContentPage>[];
  final visited = <String>{};
  final visiting = <String>{};

  void visit(HelpContentPage page) {
    if (visited.contains(page.key)) return;
    if (!visiting.add(page.key)) return;
    visited.add(page.key);
    ordered.add(page);

    final children = childrenByParentKey[page.key] ?? const <HelpContentPage>[];
    for (final child in _sortedHelpSiblings(children)) {
      visit(child);
    }

    visiting.remove(page.key);
  }

  for (final root in _sortedHelpSiblings(roots)) {
    visit(root);
  }
  for (final page in _sortedHelpSiblings(pageByKey.values)) {
    visit(page);
  }

  return ordered;
}

int helpPageDepth(
  HelpContentPage page,
  Iterable<HelpContentPage> pages, {
  int maxDepth = 6,
}) {
  final lookup = {for (final item in pages) item.key: item};
  var depth = 0;
  var parentKey = page.parentKey;
  final visited = <String>{page.key};
  while (parentKey != null && lookup[parentKey] != null && depth < maxDepth) {
    if (!visited.add(parentKey)) break;
    depth += 1;
    parentKey = lookup[parentKey]?.parentKey;
  }
  return depth;
}

String? helpPageParentTitle(
  HelpContentPage page,
  Iterable<HelpContentPage> pages,
) {
  final parentKey = page.parentKey;
  if (parentKey == null) return null;
  for (final candidate in pages) {
    if (candidate.key == parentKey) return candidate.title;
  }
  return parentKey;
}

HelpContentTreeStats helpContentTreeStats(Iterable<HelpContentPage> pages) {
  final pageList = pages.toList(growable: false);
  final keys = pageList.map((page) => page.key).toSet();
  var rootCount = 0;
  var childCount = 0;
  var orphanCount = 0;

  for (final page in pageList) {
    final parentKey = page.parentKey;
    if (parentKey == null) {
      rootCount += 1;
    } else if (keys.contains(parentKey)) {
      childCount += 1;
    } else {
      orphanCount += 1;
    }
  }

  return HelpContentTreeStats(
    rootCount: rootCount,
    childCount: childCount,
    orphanCount: orphanCount,
  );
}

class HelpContentTreeStats {
  const HelpContentTreeStats({
    required this.rootCount,
    required this.childCount,
    required this.orphanCount,
  });

  final int rootCount;
  final int childCount;
  final int orphanCount;
}

List<HelpContentPage> _sortedHelpSiblings(Iterable<HelpContentPage> pages) {
  return pages.toList(growable: false)..sort((left, right) {
    final orderDelta = left.sortOrder.compareTo(right.sortOrder);
    if (orderDelta != 0) return orderDelta;
    return left.key.compareTo(right.key);
  });
}
