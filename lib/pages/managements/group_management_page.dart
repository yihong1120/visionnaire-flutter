import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../providers/unified_auth_provider.dart';
import '../../services/management_api_service.dart';
import '../../widgets/confirmation_dialog_actions.dart';
import '../../widgets/management_feedback.dart';
import '../../widgets/responsive_scaffold.dart';

class GroupManagementPage extends StatefulWidget {
  const GroupManagementPage({super.key});
  @override
  State<GroupManagementPage> createState() => _GroupManagementPageState();
}

class _GroupManagementPageState extends State<GroupManagementPage> {
  /* ---------- 新增群組 ---------- */
  final _addFormKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _uniformCtrl = TextEditingController();

  /* ---------- 清單 ---------- */
  List<dynamic> _groups = [];
  bool _loading = false;
  String? _error;

  /* ---------- token refresh ---------- */
  Future<T> _runWithRefresh<T>(Future<T> Function(String tk) f) async {
    final auth = context.read<UnifiedAuthProvider>();
    String? tk = auth.requestToken;
    if (tk == null) throw Exception('Not logged in');
    try {
      return await f(tk);
    } catch (e) {
      final m = e.toString();
      if (m.contains('expired_token') ||
          m.contains('invalid') ||
          m.contains('replaced')) {
        await auth.refreshIfNeeded();
        tk = auth.requestToken;
        if (tk == null) throw Exception('Refresh failed');
        return await f(tk);
      }
      rethrow;
    }
  }

  /* ---------- init ---------- */
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGroups());
  }

  Future<void> _loadGroups() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _groups = await _runWithRefresh(
          (tk) => ManagementAPIService.listGroups(token: tk));
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /* ---------- add ---------- */
  Future<void> _createGroup() async {
    if (!_addFormKey.currentState!.validate()) return;
    try {
      await _runWithRefresh((tk) => ManagementAPIService.createGroup(
            name: _nameCtrl.text.trim(),
            uniformNumber: _uniformCtrl.text.trim(),
            token: tk,
          ));
      if (!mounted) return;
      showManagementSnackBar(context, AppLocalizations.of(context)!.added);
      _nameCtrl.clear();
      _uniformCtrl.clear();
      await _loadGroups();
    } catch (e) {
      if (mounted) {
        showManagementErrorSnackBar(context, e);
      }
    }
  }

  /* ---------- delete ---------- */
  Future<void> _delete(int id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.confirmDelete),
        content: Text(AppLocalizations.of(context)!.deleteWarning(name)),
        actions: buildConfirmationDialogActions(
          context: context,
          cancelLabel: AppLocalizations.of(context)!.cancel,
          confirmLabel: AppLocalizations.of(context)!.delete,
          isDestructive: true,
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _runWithRefresh(
          (tk) => ManagementAPIService.deleteGroup(groupId: id, token: tk));
      if (mounted) {
        showManagementSnackBar(context, AppLocalizations.of(context)!.deleted);
        await _loadGroups();
      }
    } catch (e) {
      if (mounted) {
        showManagementErrorSnackBar(context, e);
      }
    }
  }

  /* ---------- rename / update uniform ---------- */
  Future<void> _edit(int id, String oldName, String oldUniform) async {
    final nameCtrl = TextEditingController(text: oldName);
    final uniCtrl = TextEditingController(text: oldUniform);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.editGroup),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.name),
            ),
            TextField(
              controller: uniCtrl,
              decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.uniformNumber),
              maxLength: 8,
              keyboardType: TextInputType.number,
            ),
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

    final newName = nameCtrl.text.trim();
    final newUni = uniCtrl.text.trim();

    if (newName == oldName && newUni == oldUniform) return; // nothing changed
    if (newUni.isNotEmpty && (!RegExp(r'^\d{8}$').hasMatch(newUni))) {
      if (!mounted) return;
      showManagementSnackBar(
        context,
        AppLocalizations.of(context)!.uniformNumberError,
      );
      return;
    }

    try {
      await _runWithRefresh((tk) => ManagementAPIService.updateGroup(
            groupId: id,
            newName: newName != oldName ? newName : null,
            newUniformNumber: newUni != oldUniform ? newUni : null,
            token: tk,
          ));
      if (mounted) {
        showManagementSnackBar(context, AppLocalizations.of(context)!.updated);
        await _loadGroups();
      }
    } catch (e) {
      if (mounted) {
        showManagementErrorSnackBar(context, e);
      }
    }
  }

  /* ---------- 顯示新增群組對話框 ---------- */
  Future<void> _showAddGroupDialog() async {
    // 重置表單
    _nameCtrl.clear();
    _uniformCtrl.clear();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.addGroup),
        content: SingleChildScrollView(
          child: Form(
            key: _addFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.groupName),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? AppLocalizations.of(context)!.required
                      : null,
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _uniformCtrl,
                  decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.uniformNumber),
                  maxLength: 8,
                  keyboardType: TextInputType.number,
                  validator: (v) => (v == null ||
                          !RegExp(r'^\d{8}$').hasMatch(v))
                      ? AppLocalizations.of(context)!.uniformNumberValidation
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: buildConfirmationDialogActions(
          context: context,
          cancelLabel: AppLocalizations.of(context)!.cancel,
          confirmLabel: AppLocalizations.of(context)!.add,
          confirmIcon: Icons.add_business,
        ),
      ),
    );

    if (ok == true) {
      await _createGroup();
    }
  }

  /* ---------- UI ---------- */
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<UnifiedAuthProvider>();
    if (!auth.isSuperAdmin) {
      return ResponsiveScaffold(
        title: AppLocalizations.of(context)!.groupManagement,
        body:
            Center(child: Text(AppLocalizations.of(context)!.permissionDenied)),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 600; // 寬螢幕閾值
    final ColorScheme colors = Theme.of(context).colorScheme;

    final listWidget = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text(_error!))
            : _groups.isEmpty
                ? Center(child: Text(AppLocalizations.of(context)!.noGroups))
                : ListView.separated(
                    itemCount: _groups.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final g = _groups[i];
                      return ListTile(
                        title: Text(g['name']),
                        subtitle: Text(AppLocalizations.of(context)!
                            .uniformLabel(g['uniform_number'] ?? '－')),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit, color: colors.primary),
                              tooltip: AppLocalizations.of(context)!.edit,
                              onPressed: () => _edit(g['id'], g['name'],
                                  g['uniform_number'] ?? ''),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, color: colors.error),
                              tooltip: AppLocalizations.of(context)!.delete,
                              onPressed: () => _delete(g['id'], g['name']),
                            ),
                          ],
                        ),
                      );
                    },
                  );

    // 寬螢幕佈局：保持原設計（底部表單）
    if (isWideScreen) {
      final addSection = Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _addFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context)!.addGroup,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                          labelText: AppLocalizations.of(context)!.groupName),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? AppLocalizations.of(context)!.required
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _uniformCtrl,
                      decoration: InputDecoration(
                          labelText:
                              AppLocalizations.of(context)!.uniformNumber),
                      maxLength: 8,
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          (v == null || !RegExp(r'^\d{8}$').hasMatch(v))
                              ? AppLocalizations.of(context)!
                                  .uniformNumberValidation
                              : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _createGroup,
                    icon: const Icon(Icons.add_business),
                    label: Text(AppLocalizations.of(context)!.add),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      return ResponsiveScaffold(
        title: AppLocalizations.of(context)!.groupManagement,
        body: Column(
          children: [
            Expanded(child: listWidget),
            const Divider(height: 1),
            addSection,
          ],
        ),
      );
    }

    // 小螢幕佈局：使用浮動按鈕
    return ResponsiveScaffold(
      title: AppLocalizations.of(context)!.groupManagement,
      body: listWidget,
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: () => _showAddGroupDialog(),
        tooltip: AppLocalizations.of(context)!.addGroup,
        child: const Icon(Icons.add_business),
      ),
    );
  }
}
