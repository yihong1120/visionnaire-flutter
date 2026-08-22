import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/unified_auth_provider.dart';
import '../../services/management_api_service.dart';
import '../../utils/auth_utils.dart';
import '../../widgets/confirmation_dialog_actions.dart';
import '../../widgets/management_feedback.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../widgets/stream_config_dialog.dart';

class SiteManagementPage extends StatefulWidget {
  const SiteManagementPage({super.key});

  @override
  State<SiteManagementPage> createState() => _SiteManagementPageState();
}

class _SiteManagementPageState extends State<SiteManagementPage> {
  bool _loading = false;
  String? _error;

  List<_SiteRecord> _sites = <_SiteRecord>[];
  List<_UserRecord> _users = <_UserRecord>[];
  List<_GroupRecord> _groups = <_GroupRecord>[];

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
      final auth = context.read<UnifiedAuthProvider>();
      final local = AppLocalizations.of(context)!;

      final rawSites = await AuthUtils.withAuthRetryOnError(
        context,
        (token) => ManagementAPIService.listSites(token: token),
      );
      if (!mounted) return;

      final List<_SiteRecord> parsedSites = rawSites
          .whereType<Map>()
          .map((site) => _SiteRecord.fromJson(Map<String, dynamic>.from(site)))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      List<_UserRecord> parsedUsers = <_UserRecord>[];
      if (auth.isSuperAdmin || auth.role == 'admin') {
        final rawUsers = await AuthUtils.withAuthRetryOnError(
          context,
          (token) => ManagementAPIService.listUsers(token: token),
        );
        if (!mounted) return;

        parsedUsers = rawUsers
            .whereType<Map>()
            .map(
                (user) => _UserRecord.fromJson(Map<String, dynamic>.from(user)))
            .toList()
          ..sort((a, b) =>
              a.username.toLowerCase().compareTo(b.username.toLowerCase()));
      }

      List<_GroupRecord> parsedGroups = <_GroupRecord>[];
      if (auth.isSuperAdmin) {
        final rawGroups = await AuthUtils.withAuthRetryOnError(
          context,
          (token) => ManagementAPIService.listGroups(token: token),
        );
        if (!mounted) return;

        parsedGroups = rawGroups
            .whereType<Map>()
            .map((group) =>
                _GroupRecord.fromJson(Map<String, dynamic>.from(group)))
            .toList()
          ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else if (auth.groupId != null) {
        parsedGroups = <_GroupRecord>[
          _GroupRecord(
            id: auth.groupId!,
            name: _resolveScopedGroupName(
              auth.groupId!,
              parsedSites,
              parsedUsers,
              local.group,
            ),
          ),
        ];
      }

      if (!mounted) return;
      setState(() {
        _sites = parsedSites;
        _users = parsedUsers;
        _groups = parsedGroups;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _resolveScopedGroupName(
    int groupId,
    List<_SiteRecord> sites,
    List<_UserRecord> users,
    String fallbackLabel,
  ) {
    for (final site in sites) {
      final String? name = site.groupNameFor(groupId);
      if (name != null && name.trim().isNotEmpty) return name;
    }

    for (final user in users) {
      if (user.groupId == groupId &&
          (user.groupName?.trim().isNotEmpty ?? false)) {
        return user.groupName!.trim();
      }
    }

    return '$fallbackLabel $groupId';
  }

  List<_GroupRecord> _availableGroupsForEditor(UnifiedAuthProvider auth) {
    if (auth.isSuperAdmin) return _groups;
    if (auth.groupId == null) return _groups;
    final scopedGroups =
        _groups.where((group) => group.id == auth.groupId).toList();
    return scopedGroups.isEmpty ? _groups : scopedGroups;
  }

  List<_UserRecord> _availableUsersForSite(_SiteRecord site) {
    if (site.groupIds.isEmpty) return _users;
    return _users
        .where((user) =>
            user.groupId != null && site.groupIds.contains(user.groupId))
        .toList();
  }

  Future<void> _createSite() async {
    final _SiteEditorResult? result = await _showSiteEditorDialog();
    if (result == null || !mounted) return;

    try {
      await AuthUtils.withAuthRetryOnError(
        context,
        (token) => ManagementAPIService.createSite(
          name: result.name,
          groupIds: result.groupIds.toList(),
          token: token,
        ),
      );
      if (!mounted) return;
      showManagementSnackBar(
          context, AppLocalizations.of(context)!.siteCreated);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      showManagementErrorSnackBar(context, error);
    }
  }

  Future<void> _editSite(_SiteRecord site) async {
    final _SiteEditorResult? result = await _showSiteEditorDialog(site: site);
    if (result == null || !mounted) return;

    final Set<int> previousGroupIds = site.groupIds.toSet();
    final Set<int> nextGroupIds = result.groupIds;
    final Set<int> toAdd = nextGroupIds.difference(previousGroupIds);
    final Set<int> toRemove = previousGroupIds.difference(nextGroupIds);
    final bool nameChanged = result.name != site.name;

    if (!nameChanged && toAdd.isEmpty && toRemove.isEmpty) return;

    try {
      await AuthUtils.withAuthRetryOnError(context, (token) async {
        if (nameChanged) {
          await ManagementAPIService.updateSite(
            siteId: site.id,
            newName: result.name,
            token: token,
          );
        }

        for (final groupId in toAdd) {
          await ManagementAPIService.addGroupToSite(
            siteId: site.id,
            groupId: groupId,
            token: token,
          );
        }

        for (final groupId in toRemove) {
          await ManagementAPIService.removeGroupFromSite(
            siteId: site.id,
            groupId: groupId,
            token: token,
          );
        }
      });

      if (!mounted) return;
      showManagementSnackBar(context, AppLocalizations.of(context)!.updated);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      showManagementErrorSnackBar(context, error);
    }
  }

  Future<void> _deleteSite(_SiteRecord site) async {
    final local = AppLocalizations.of(context)!;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(local.confirmDelete),
        content: Text(local.permanentDeleteWarning(site.name)),
        actions: buildConfirmationDialogActions(
          context: dialogContext,
          cancelLabel: local.cancel,
          confirmLabel: local.delete,
          isDestructive: true,
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await AuthUtils.withAuthRetryOnError(
        context,
        (token) =>
            ManagementAPIService.deleteSite(siteId: site.id, token: token),
      );
      if (!mounted) return;
      showManagementSnackBar(context, local.deleted);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      showManagementErrorSnackBar(context, error);
    }
  }

  Future<_SiteEditorResult?> _showSiteEditorDialog({_SiteRecord? site}) async {
    final auth = context.read<UnifiedAuthProvider>();
    final local = AppLocalizations.of(context)!;
    final List<_GroupRecord> groups = _availableGroupsForEditor(auth);
    final TextEditingController nameController =
        TextEditingController(text: site?.name ?? '');
    final Set<int> selectedGroupIds =
        _initialSelectedGroupIds(auth, site, groups);
    String? validationMessage;

    final _SiteEditorResult? result = await showDialog<_SiteEditorResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(site == null ? local.add : local.edit),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(labelText: local.siteName),
                    onChanged: (_) {
                      if (validationMessage != null) {
                        setDialogState(() => validationMessage = null);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    local.group,
                    style: Theme.of(dialogContext).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (groups.isEmpty)
                    Text(local.noGroups)
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: groups.map((group) {
                        final bool selected =
                            selectedGroupIds.contains(group.id);
                        return FilterChip(
                          label: Text(group.name),
                          selected: selected,
                          onSelected: auth.isSuperAdmin
                              ? (value) {
                                  setDialogState(() {
                                    validationMessage = null;
                                    if (value) {
                                      selectedGroupIds.add(group.id);
                                    } else {
                                      selectedGroupIds.remove(group.id);
                                    }
                                  });
                                }
                              : null,
                        );
                      }).toList(),
                    ),
                  if (validationMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      validationMessage!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(local.cancel),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final String name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => validationMessage = local.required);
                  return;
                }
                if (groups.isNotEmpty && selectedGroupIds.isEmpty) {
                  setDialogState(() => validationMessage = local.selectGroup);
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _SiteEditorResult(name: name, groupIds: selectedGroupIds),
                );
              },
              icon: Icon(site == null ? Icons.add_location_alt : Icons.save),
              label: Text(site == null ? local.add : local.save),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    return result;
  }

  Future<void> _manageUsersOfSite(_SiteRecord site) async {
    final local = AppLocalizations.of(context)!;
    final List<_UserRecord> availableUsers = _availableUsersForSite(site);
    final Set<int> original = site.userIds.toSet();
    final Set<int> current = site.userIds.toSet();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(local.managementTitle(site.name)),
        content: SizedBox(
          width: 520,
          child: StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              if (availableUsers.isEmpty) {
                return Text(local.noUsers);
              }

              return ListView(
                shrinkWrap: true,
                children: availableUsers.map((user) {
                  return CheckboxListTile(
                    value: current.contains(user.id),
                    title: Text(user.username),
                    subtitle:
                        user.groupName == null ? null : Text(user.groupName!),
                    onChanged: (value) {
                      setDialogState(() {
                        if (value == true) {
                          current.add(user.id);
                        } else {
                          current.remove(user.id);
                        }
                      });
                    },
                  );
                }).toList(),
              );
            },
          ),
        ),
        actions: buildConfirmationDialogActions(
          context: dialogContext,
          cancelLabel: local.cancel,
          confirmLabel: local.confirm,
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final Set<int> toAdd = current.difference(original);
    final Set<int> toRemove = original.difference(current);
    if (toAdd.isEmpty && toRemove.isEmpty) return;

    try {
      await AuthUtils.withAuthRetryOnError(context, (token) async {
        for (final userId in toAdd) {
          await ManagementAPIService.addUserToSite(
            siteId: site.id,
            userId: userId,
            token: token,
          );
        }
        for (final userId in toRemove) {
          await ManagementAPIService.removeUserFromSite(
            siteId: site.id,
            userId: userId,
            token: token,
          );
        }
      });

      if (!mounted) return;
      showManagementSnackBar(context, local.userUpdated);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      showManagementErrorSnackBar(context, error);
    }
  }

  Set<int> _initialSelectedGroupIds(
    UnifiedAuthProvider auth,
    _SiteRecord? site,
    List<_GroupRecord> groups,
  ) {
    if (site != null && site.groupIds.isNotEmpty) {
      if (auth.isSuperAdmin) return site.groupIds.toSet();
      if (auth.groupId != null && site.groupIds.contains(auth.groupId)) {
        return <int>{auth.groupId!};
      }
    }

    if (auth.groupId != null) return <int>{auth.groupId!};
    if (groups.length == 1) return <int>{groups.first.id};
    return <int>{};
  }

  Future<void> _openStreamConfigDialog(_SiteRecord site) async {
    final bool? refreshed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StreamConfigDialog(
        site: site.toStreamSiteMap(),
      ),
    );

    if (refreshed == true && mounted) {
      await _loadData();
    }
  }

  bool _canConfigureStream(UnifiedAuthProvider auth) {
    return auth.isSuperAdmin || auth.role == 'admin';
  }

  Widget _buildSummaryChip(IconData icon, int value) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text('$value'),
    );
  }

  Widget _buildSiteCard(_SiteRecord site, UnifiedAuthProvider auth) {
    final local = AppLocalizations.of(context)!;
    final List<String> groupNames =
        site.groupDisplayNames(_groups, local.group);
    final List<_UserRecord> availableUsers = _availableUsersForSite(site);
    final int assignedUserCount =
        availableUsers.where((user) => site.userIds.contains(user.id)).length;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        site.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: groupNames
                            .map((name) => Chip(label: Text(name)))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _buildSummaryChip(
                        Icons.groups_outlined, site.groupIds.length),
                    _buildSummaryChip(Icons.person_outline, assignedUserCount),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () => _editSite(site),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(local.edit),
                ),
                OutlinedButton.icon(
                  onPressed: () => _manageUsersOfSite(site),
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: Text(local.configureUsers),
                ),
                if (_canConfigureStream(auth))
                  OutlinedButton.icon(
                    onPressed: () => _openStreamConfigDialog(site),
                    icon: const Icon(Icons.video_settings_outlined),
                    label: Text(local.configureStream),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _deleteSite(site),
                  icon: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  label: Text(local.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<UnifiedAuthProvider>();
    final local = AppLocalizations.of(context)!;
    final bool isAdmin = auth.isSuperAdmin || auth.role == 'admin';

    if (!isAdmin) {
      return ResponsiveScaffold(
        title: local.siteManagement,
        body: Center(child: Text(local.permissionDenied)),
      );
    }

    final List<_SiteRecord> visibleSites = _sites;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(child: Text(_error!));
    } else if (visibleSites.isEmpty) {
      body = Center(child: Text(local.noSites));
    } else {
      body = RefreshIndicator(
        onRefresh: _loadData,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: visibleSites.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, index) => _buildSiteCard(visibleSites[index], auth),
        ),
      );
    }

    return ResponsiveScaffold(
      title: local.siteManagement,
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _createSite,
        icon: const Icon(Icons.add_location_alt),
        label: Text(local.add),
      ),
    );
  }
}

class _SiteEditorResult {
  _SiteEditorResult({required this.name, required Set<int> groupIds})
      : groupIds = Set<int>.from(groupIds);

  final String name;
  final Set<int> groupIds;
}

class _GroupRecord {
  const _GroupRecord({required this.id, required this.name});

  factory _GroupRecord.fromJson(Map<String, dynamic> json) {
    return _GroupRecord(
      id: _toInt(json['group_id'] ?? json['id']),
      name: (json['group_name'] ?? json['name'] ?? '').toString(),
    );
  }

  final int id;
  final String name;
}

class _UserRecord {
  const _UserRecord({
    required this.id,
    required this.username,
    required this.groupId,
    required this.groupName,
  });

  factory _UserRecord.fromJson(Map<String, dynamic> json) {
    return _UserRecord(
      id: _toInt(json['id'] ?? json['user_id']),
      username: (json['username'] ?? '').toString(),
      groupId: _toNullableInt(json['group_id']),
      groupName: _toNullableString(json['group_name']),
    );
  }

  final int id;
  final String username;
  final int? groupId;
  final String? groupName;
}

class _SiteRecord {
  const _SiteRecord({
    required this.id,
    required this.name,
    required this.groupIds,
    required this.groupNames,
    required this.userIds,
  });

  factory _SiteRecord.fromJson(Map<String, dynamic> json) {
    return _SiteRecord(
      id: _toInt(json['id'] ?? json['site_id']),
      name: (json['name'] ?? '').toString(),
      groupIds: _toIntList(json['group_ids']),
      groupNames: _toStringList(json['group_names']),
      userIds: _toIntList(json['user_ids']),
    );
  }

  final int id;
  final String name;
  final List<int> groupIds;
  final List<String> groupNames;
  final List<int> userIds;

  String? groupNameFor(int groupId) {
    final int index = groupIds.indexOf(groupId);
    if (index == -1) return null;
    if (index < groupNames.length) {
      final String name = groupNames[index].trim();
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  List<String> groupDisplayNames(
      List<_GroupRecord> groups, String fallbackLabel) {
    if (groupIds.isEmpty) return <String>[fallbackLabel];

    final List<String> resolved = <String>[];
    for (final groupId in groupIds) {
      final String? existing = groupNameFor(groupId);
      if (existing != null) {
        resolved.add(existing);
        continue;
      }

      String? fallbackName;
      for (final group in groups) {
        if (group.id == groupId) {
          fallbackName = group.name;
          break;
        }
      }
      resolved.add(fallbackName ?? '$fallbackLabel $groupId');
    }
    return resolved;
  }

  Map<String, dynamic> toStreamSiteMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
    };
  }
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.parse(value.toString());
}

int? _toNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

String? _toNullableString(Object? value) {
  if (value == null) return null;
  final String normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

List<int> _toIntList(Object? value) {
  if (value is! List) return <int>[];
  return value.map(_toInt).toList();
}

List<String> _toStringList(Object? value) {
  if (value is! List) return <String>[];
  return value.map((item) => item.toString()).toList();
}
