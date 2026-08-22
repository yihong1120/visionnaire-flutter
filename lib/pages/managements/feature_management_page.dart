import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../providers/unified_auth_provider.dart';
import '../../services/management_api_service.dart';
import '../../widgets/confirmation_dialog_actions.dart';
import '../../widgets/management_feedback.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../utils/auth_utils.dart';

class FeatureManagementPage extends StatefulWidget {
  const FeatureManagementPage({super.key});

  @override
  State<FeatureManagementPage> createState() => _FeatureManagementPageState();
}

class _FeatureManagementPageState extends State<FeatureManagementPage> {
  /* ---------- form ---------- */
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  /* ---------- state ---------- */
  bool _loading = false;
  String? _error;
  List<dynamic> _features = [];
  List<dynamic> _groups = [];
  Map<int, Set<int>> _group2feat = {}; // group_id -> featureIds

  /* ---------- init ---------- */
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      _features = await AuthUtils.withAuthRetryOnError(
          context, (tk) => ManagementAPIService.listFeatures(token: tk));

      if (!mounted) return;

      _groups = await AuthUtils.withAuthRetryOnError(
          context, (tk) => ManagementAPIService.listGroups(token: tk));

      if (!mounted) return;

      final gf = await AuthUtils.withAuthRetryOnError(
          context, (tk) => ManagementAPIService.listGroupFeatures(token: tk));
      _group2feat = {
        for (final g in gf)
          g['group_id'] as int: Set<int>.from(g['feature_ids'] as List)
      };
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /* ---------- create ---------- */
  Future<void> _createFeature() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await AuthUtils.withAuthRetryOnError(
          context,
          (tk) => ManagementAPIService.createFeature(
                featureName: _nameCtrl.text.trim(),
                description: _descCtrl.text.trim().isEmpty
                    ? null
                    : _descCtrl.text.trim(),
                token: tk,
              ));
      _nameCtrl.clear();
      _descCtrl.clear();
      if (!mounted) return;
      if (mounted) {
        showManagementSnackBar(
          context,
          AppLocalizations.of(context)!.featureAdded,
        );
        await _loadData();
      }
    } catch (e) {
      if (!mounted) return;
      showManagementErrorSnackBar(context, e);
    }
  }

  /* ---------- delete ---------- */
  Future<void> _deleteFeature(int fid, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.confirmDelete),
        content:
            Text(AppLocalizations.of(context)!.deleteFeatureConfirmation(name)),
        actions: buildConfirmationDialogActions(
          context: context,
          cancelLabel: AppLocalizations.of(context)!.cancel,
          confirmLabel: AppLocalizations.of(context)!.delete,
          isDestructive: true,
        ),
      ),
    );
    if (ok != true) return;

    if (!mounted) return;

    try {
      await AuthUtils.withAuthRetryOnError(
          context,
          (tk) =>
              ManagementAPIService.deleteFeature(featureId: fid, token: tk));
      if (mounted) {
        showManagementSnackBar(context, AppLocalizations.of(context)!.deleted);
        await _loadData();
      }
    } catch (e) {
      if (!mounted) return;
      showManagementErrorSnackBar(context, e);
    }
  }

  /* ---------- edit ---------- */
  Future<void> _editFeature(Map feat) async {
    final id = feat['id'] as int;
    final name = feat['feature_name'] as String;
    final desc = feat['description'] as String? ?? '';

    final nameCtrl = TextEditingController(text: name);
    final descCtrl = TextEditingController(text: desc);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.editFeature(name)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.featureName)),
            TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                    labelText:
                        AppLocalizations.of(context)!.descriptionOptional)),
          ],
        ),
        actions: buildConfirmationDialogActions(
          context: context,
          cancelLabel: AppLocalizations.of(context)!.cancel,
          confirmLabel: AppLocalizations.of(context)!.confirm,
        ),
      ),
    );
    if (ok != true) return;

    if (!mounted) return;

    try {
      await AuthUtils.withAuthRetryOnError(
          context,
          (tk) => ManagementAPIService.updateFeature(
                featureId: id,
                newName: nameCtrl.text.trim(),
                newDescription: descCtrl.text.trim(),
                token: tk,
              ));
      if (mounted) {
        showManagementSnackBar(context, AppLocalizations.of(context)!.updated);
        await _loadData();
      }
    } catch (e) {
      if (!mounted) return;
      showManagementErrorSnackBar(context, e);
    }
  }

  /* ---------- assign groups ---------- */
  Future<void> _assignGroups(Map feat) async {
    final fid = feat['id'] as int;
    final fname = feat['feature_name'] as String;

    final original = <int>{
      for (final entry in _group2feat.entries)
        if (entry.value.contains(fid)) entry.key
    }; // 原本就有勾的 gid

    final selected = {...original};

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        // ★★★ 關鍵：對話框自己持 state
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.assignGroups(fname)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _groups.length,
              itemBuilder: (context, index) {
                final g = _groups[index];
                final gid = g['id'] as int;
                final gname = g['name'] as String;
                final checked = selected.contains(gid);
                return CheckboxListTile(
                  title: Text(gname),
                  value: checked,
                  onChanged: (v) {
                    setStateDialog(() {
                      // ← 只重繪 dialog
                      if (v == true) {
                        selected.add(gid);
                      } else {
                        selected.remove(gid);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: buildConfirmationDialogActions(
            context: context,
            cancelLabel: AppLocalizations.of(context)!.cancel,
            confirmLabel: AppLocalizations.of(context)!.confirm,
          ),
        ),
      ),
    );
    if (ok != true) return;

    if (!mounted) return;

    try {
      await AuthUtils.withAuthRetryOnError(context, (tk) async {
        for (final g in _groups) {
          final gid = g['id'] as int;
          final currentSet = _group2feat[gid] ?? <int>{};
          final wantSet = {...currentSet};

          if (selected.contains(gid)) {
            wantSet.add(fid);
          } else {
            wantSet.remove(fid);
          }

          if (wantSet.length == currentSet.length &&
              wantSet.containsAll(currentSet)) {
            continue; // 沒改動
          }

          await ManagementAPIService.updateGroupFeature(
            groupId: gid,
            featureIds: wantSet.toList(),
            token: tk,
          );
        }
      });
      if (mounted) {
        showManagementSnackBar(
          context,
          AppLocalizations.of(context)!.groupPermissionsUpdated,
        );
        await _loadData();
      }
    } catch (e) {
      if (!mounted) return;
      showManagementErrorSnackBar(context, e);
    }
  }

  /* ---------- 顯示新增功能對話框 ---------- */
  Future<void> _showAddFeatureDialog() async {
    // 重置表單
    _nameCtrl.clear();
    _descCtrl.clear();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.addFeature),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.featureName),
                validator: (v) => v == null || v.trim().isEmpty
                    ? AppLocalizations.of(context)!.required
                    : null,
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descCtrl,
                decoration: InputDecoration(
                    labelText:
                        AppLocalizations.of(context)!.descriptionOptional),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: buildConfirmationDialogActions(
          context: context,
          cancelLabel: AppLocalizations.of(context)!.cancel,
          confirmLabel: AppLocalizations.of(context)!.add,
          confirmIcon: Icons.extension,
        ),
      ),
    );

    if (ok == true) {
      await _createFeature();
    }
  }

  /* ---------- build ---------- */
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<UnifiedAuthProvider>();
    if (!auth.isSuperAdmin) {
      return ResponsiveScaffold(
        title: AppLocalizations.of(context)!.featureManagement,
        body:
            Center(child: Text(AppLocalizations.of(context)!.permissionDenied)),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 600; // 寬螢幕閾值

    // ---------- list ----------
    Widget listArea;
    if (_loading) {
      listArea = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      listArea = Center(child: Text(_error!));
    } else if (_features.isEmpty) {
      listArea = Center(child: Text(AppLocalizations.of(context)!.noFeatures));
    } else {
      listArea = ListView.separated(
        itemCount: _features.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int i) {
          final ColorScheme colors = Theme.of(context).colorScheme;
          final f = _features[i];
          return ListTile(
            title: Text(f['feature_name']),
            subtitle: Text(f['description'] ?? '-'),
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  icon: Icon(Icons.group, color: colors.secondary),
                  tooltip: AppLocalizations.of(context)!.setGroups,
                  onPressed: () => _assignGroups(f),
                ),
                IconButton(
                  icon: Icon(Icons.edit, color: colors.primary),
                  tooltip: AppLocalizations.of(context)!.edit,
                  onPressed: () => _editFeature(f),
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: colors.error),
                  tooltip: AppLocalizations.of(context)!.delete,
                  onPressed: () => _deleteFeature(f['id'], f['feature_name']),
                ),
              ],
            ),
          );
        },
      );
    }

    // 寬螢幕佈局：保持原設計（底部表單）
    if (isWideScreen) {
      final createSection = Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context)!.addFeature,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.featureName),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? AppLocalizations.of(context)!.required
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _descCtrl,
                      decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!
                              .descriptionOptional),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.extension),
                    label: Text(AppLocalizations.of(context)!.add),
                    onPressed: _createFeature,
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      return ResponsiveScaffold(
        title: AppLocalizations.of(context)!.featureManagement,
        body: Column(
          children: [
            Expanded(child: listArea),
            const Divider(height: 1),
            createSection,
          ],
        ),
      );
    }

    // 小螢幕佈局：使用浮動按鈕
    return ResponsiveScaffold(
      title: AppLocalizations.of(context)!.featureManagement,
      body: listArea,
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: () => _showAddFeatureDialog(),
        tooltip: AppLocalizations.of(context)!.addFeature,
        child: const Icon(Icons.extension),
      ),
    );
  }
}
