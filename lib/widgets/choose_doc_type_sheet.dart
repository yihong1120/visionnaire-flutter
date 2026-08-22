import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/file_manage_api_service.dart';
import '../utils/auth_utils.dart';

/// A bottom sheet widget for selecting a document type.
///
/// Fetches available categories and types from the backend, and allows the user to select a type.
/// The result is returned as a map containing the selected category, type, and file prefix.
class ChooseDocTypeSheet extends StatefulWidget {
  /// Creates a [ChooseDocTypeSheet] widget.
  const ChooseDocTypeSheet({super.key});

  @override
  State<ChooseDocTypeSheet> createState() => _ChooseDocTypeSheetState();
}

/// State for [ChooseDocTypeSheet]. Handles fetching categories/types and user selection.
class _ChooseDocTypeSheetState extends State<ChooseDocTypeSheet> {
  /// Whether the widget is currently loading data.
  bool _loading = true;

  /// Error message, if any, from fetching data.
  String? _err;

  /// List of category objects fetched from the backend.
  List<dynamic> _cats = <dynamic>[];

  /// Mapping from category ID to a list of type objects.
  final Map<int, List<dynamic>> _typesByCat =
      <int, List<dynamic>>{}; // catId → List<types>

  /// Currently selected category ID.
  int? _selCatId;

  /// Keyword used to search across category names and document type names.
  final TextEditingController _searchCtrl = TextEditingController();

  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _fetchCats();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Fetches categories and their types from the backend.
  ///
  /// Sets [_cats], [_typesByCat], and [_selCatId] accordingly.
  /// Handles errors and updates [_loading] state.
  Future<void> _fetchCats() async {
    try {
      final List<dynamic> cats = await AuthUtils.withAuthRetry(
          context, (token) => FileManageAPIService.getCategories(token: token));
      setState(() {
        _cats = cats;
        _selCatId = cats.isEmpty ? null : cats.first['id'] as int;
      });
      for (final dynamic c in cats) {
        final int cid = c['id'] as int;
        if (!mounted) return;
        _typesByCat[cid] = await AuthUtils.withAuthRetry(
            context,
            (token) =>
                FileManageAPIService.getTypes(token: token, categoryId: cid));
      }
    } catch (e) {
      _err = '$e';
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context)!;
    // Determine if the device is a phone based on width.
    final bool isPhone = MediaQuery.of(context).size.width < 600;
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.chooseDocumentTypeTitle),
          automaticallyImplyLeading: false,
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _err != null
                ? Center(child: Text(_err!))
                : Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (String value) {
                            setState(() => _keyword = value.trim());
                          },
                          decoration: InputDecoration(
                            hintText: l.documentTypeSearchHint,
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _keyword.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _keyword = '');
                                    },
                                    icon: const Icon(Icons.close),
                                    tooltip: MaterialLocalizations.of(context)
                                        .clearButtonTooltip,
                                  ),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                            builder: (BuildContext _, BoxConstraints c) {
                          if (isPhone) {
                            // Phone layout: categories on top, types below.
                            return Column(
                              children: <Widget>[
                                _catList(axis: Axis.horizontal, height: 56),
                                const Divider(height: 1),
                                Expanded(child: _typeList()),
                              ],
                            );
                          } else {
                            // Tablet/web layout: categories on the left, types on the right.
                            return Row(
                              children: <Widget>[
                                SizedBox(
                                  width: 260,
                                  child: _catList(axis: Axis.vertical),
                                ),
                                const VerticalDivider(width: 1),
                                Expanded(child: _typeList()),
                              ],
                            );
                          }
                        }),
                      ),
                    ],
                  ),
      ),
    );
  }

  bool get _hasKeyword => _keyword.isNotEmpty;

  List<Map<String, dynamic>> _visibleTypes() {
    final String query = _keyword.toLowerCase();
    final Iterable<dynamic> categories = _hasKeyword
        ? _cats
        : _cats.where((dynamic cat) => cat['id'] == _selCatId);

    final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];
    for (final dynamic cat in categories) {
      final int catId = cat['id'] as int;
      final String catName = (cat['category_name'] as String? ?? '').trim();
      final List<dynamic> types = _typesByCat[catId] ?? <dynamic>[];
      for (final dynamic type in types) {
        final String typeName = (type['type_name'] as String? ?? '').trim();
        final String prefix = (type['file_prefix'] as String? ?? '').trim();
        final bool matches = !_hasKeyword ||
            catName.toLowerCase().contains(query) ||
            typeName.toLowerCase().contains(query) ||
            prefix.toLowerCase().contains(query);
        if (matches) {
          results.add(<String, dynamic>{
            'category': cat,
            'type': type,
          });
        }
      }
    }
    return results;
  }

  /// Builds the category list widget.
  ///
  /// [axis] determines the scroll direction (vertical or horizontal).
  /// [height] sets the height for horizontal layout.
  /// Returns a [Widget] displaying the available categories as chips.
  Widget _catList({Axis axis = Axis.vertical, double? height}) {
    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: axis,
        itemCount: _cats.length,
        itemBuilder: (BuildContext _, int i) {
          final dynamic cat = _cats[i];
          final bool sel = cat['id'] == _selCatId;
          final Widget tile = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              selected: sel,
              label: Text(cat['category_name'] as String),
              onSelected: (_) => setState(() => _selCatId = cat['id'] as int),
            ),
          );
          return axis == Axis.vertical ? ListTile(title: tile) : tile;
        },
      ),
    );
  }

  /// Builds the type list widget for the selected category.
  ///
  /// Returns a [Widget] displaying the available types for the selected category.
  Widget _typeList() {
    final AppLocalizations l = AppLocalizations.of(context)!;
    if (_selCatId == null) {
      return Center(child: Text(l.noAvailableCategories));
    }
    final List<Map<String, dynamic>> visibleTypes = _visibleTypes();
    if (visibleTypes.isEmpty) {
      return Center(
        child: Text(
            _hasKeyword ? l.noMatchingDocumentTypes : l.noAvailableCategories),
      );
    }
    return ListView.separated(
      itemCount: visibleTypes.length,
      separatorBuilder: (BuildContext _, int __) => const Divider(height: 1),
      itemBuilder: (BuildContext _, int i) {
        final Map<String, dynamic> entry = visibleTypes[i];
        final dynamic t = entry['type'];
        final dynamic cat = entry['category'];
        final String prefix = (t['file_prefix'] as String? ?? '').trim();
        return ListTile(
          title: Text(t['type_name'] as String),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_hasKeyword) Text(cat['category_name'] as String? ?? ''),
              Text(
                prefix.isEmpty
                    ? l.documentTypePrefixUnset
                    : l.documentTypePrefixValue(prefix),
              ),
            ],
          ),
          onTap: () => Navigator.pop(context, <String, dynamic>{
            'category': cat,
            'type': t, // ← Original behaviour
            'file_prefix': t['file_prefix'], // ← For convenience
          }),
        );
      },
    );
  }
}
