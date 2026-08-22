import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/unified_auth_provider.dart';
import '../services/file_manage_api_service.dart';

@visibleForTesting
List<String> buildSignerSubtitleLines(
  Map<String, dynamic> user, {
  required String groupLabel,
}) {
  final List<String> lines = <String>[];
  final String fullName = _buildFullName(user);
  final String groupName = _toCleanString(user['group_name']);
  final String email = _toCleanString(user['email']);

  if (fullName.isNotEmpty) {
    lines.add(fullName);
  }
  if (groupName.isNotEmpty) {
    lines.add('$groupLabel: $groupName');
  }
  if (email.isNotEmpty) {
    lines.add(email);
  }

  return lines;
}

@visibleForTesting
bool hasSignerSelectionScope({
  int? groupId,
}) {
  return groupId != null;
}

@visibleForTesting
String buildSignerResultSummary({
  required bool isLoading,
  required int loaded,
  required int total,
  required bool hasScope,
}) {
  if (!hasScope) {
    return 'Select group to load signers';
  }

  if (isLoading && loaded == 0) {
    return 'Loading signers...';
  }

  return 'Showing $loaded / $total';
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String _toCleanString(dynamic value) {
  if (value == null) return '';
  final String text = value.toString().trim();
  return text == 'null' ? '' : text;
}

String _buildFullName(Map<String, dynamic> user) {
  final String familyName = _toCleanString(user['family_name']);
  final String givenName = _toCleanString(user['given_name']);

  if (familyName.isEmpty) return givenName;
  if (givenName.isEmpty) return familyName;

  final bool useWhitespaceSeparator =
      RegExp(r'^[A-Za-z\s\-]+?$').hasMatch(familyName) &&
          RegExp(r'^[A-Za-z\s\-]+?$').hasMatch(givenName);

  return useWhitespaceSeparator
      ? '$familyName $givenName'
      : '$familyName$givenName';
}

class SignerPicker {
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required int versionId,
    String? initialKeyword,
    int? initialGroupId,
  }) async {
    final UnifiedAuthProvider auth = context.read<UnifiedAuthProvider>();
    final String? token = auth.requestToken;
    final AppLocalizations? local = AppLocalizations.of(context);

    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid authentication token')),
      );
      return null;
    }

    try {
      String keyword = initialKeyword?.trim() ?? '';
      final List<Map<String, dynamic>> initialGroups =
          await FileManageAPIService.getSignerPickerGroups(
        token: token,
        versionId: versionId,
      );

      int? selectedGroupId = initialGroupId;
      if (!auth.isSuperAdmin && auth.groupId != null) {
        selectedGroupId = auth.groupId;
      }
      if (selectedGroupId != null &&
          !initialGroups
              .any((group) => _toInt(group['id']) == selectedGroupId)) {
        selectedGroupId = null;
      }

      const int pageSize = 50;
      final bool hasInitialScope = hasSignerSelectionScope(
        groupId: selectedGroupId,
      );
      final Map<String, dynamic> initialUsersResponse = hasInitialScope
          ? await FileManageAPIService.getSigners(
              token: token,
              keyword: keyword.isEmpty ? null : keyword,
              groupId: selectedGroupId,
              versionId: versionId,
              limit: pageSize,
              offset: 0,
            )
          : <String, dynamic>{'total': 0, 'items': <dynamic>[]};

      if (!context.mounted) return null;

      return await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (BuildContext sheetContext) {
          final TextEditingController searchCtl =
              TextEditingController(text: keyword);
          Timer? debounce;
          List<Map<String, dynamic>> currentGroups =
              List<Map<String, dynamic>>.from(initialGroups);
          List<Map<String, dynamic>> users = List<Map<String, dynamic>>.from(
            (initialUsersResponse['items'] as List<dynamic>)
                .map((dynamic item) => Map<String, dynamic>.from(item as Map)),
          );
          int total = _toInt(initialUsersResponse['total']) ?? users.length;
          int offset = users.length;
          bool isLoadingGroups = false;
          bool isLoadingUsers = false;
          bool isLoadingMore = false;

          Future<void> loadUsers(
            void Function(void Function()) setStateFn, {
            bool append = false,
          }) async {
            final bool hasScope = hasSignerSelectionScope(
              groupId: selectedGroupId,
            );

            if (!hasScope) {
              setStateFn(() {
                users = <Map<String, dynamic>>[];
                total = 0;
                offset = 0;
                isLoadingUsers = false;
                isLoadingMore = false;
              });
              return;
            }

            setStateFn(() {
              if (append) {
                isLoadingMore = true;
              } else {
                isLoadingUsers = true;
              }
            });

            try {
              final Map<String, dynamic> response =
                  await FileManageAPIService.getSigners(
                token: token,
                keyword: keyword.isEmpty ? null : keyword,
                groupId: selectedGroupId,
                versionId: versionId,
                limit: pageSize,
                offset: append ? offset : 0,
              );
              if (!sheetContext.mounted) return;

              final List<Map<String, dynamic>> nextItems = (response['items']
                      as List<dynamic>)
                  .map((dynamic item) =>
                      Map<String, dynamic>.from(item as Map<dynamic, dynamic>))
                  .toList();

              setStateFn(() {
                users = append
                    ? <Map<String, dynamic>>[...users, ...nextItems]
                    : nextItems;
                total = _toInt(response['total']) ?? users.length;
                offset = users.length;
                isLoadingUsers = false;
                isLoadingMore = false;
              });
            } catch (error) {
              if (!sheetContext.mounted) return;
              setStateFn(() {
                isLoadingUsers = false;
                isLoadingMore = false;
              });
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(content: Text('Failed to load signers: $error')),
              );
            }
          }

          Future<void> loadGroupsAndUsers(
            void Function(void Function()) setStateFn,
          ) async {
            setStateFn(() {
              isLoadingGroups = true;
              isLoadingUsers = true;
              isLoadingMore = false;
              currentGroups = <Map<String, dynamic>>[];
              users = <Map<String, dynamic>>[];
              total = 0;
              offset = 0;
            });

            try {
              final List<Map<String, dynamic>> nextGroups =
                  await FileManageAPIService.getSignerPickerGroups(
                token: token,
                versionId: versionId,
              );

              if (selectedGroupId != null &&
                  !nextGroups
                      .any((group) => _toInt(group['id']) == selectedGroupId)) {
                selectedGroupId = null;
              }
              if (!auth.isSuperAdmin && auth.groupId != null) {
                final bool hasScopedGroup = nextGroups.any(
                  (group) => _toInt(group['id']) == auth.groupId,
                );
                if (hasScopedGroup) {
                  selectedGroupId = auth.groupId;
                }
              }

              final bool hasScope = hasSignerSelectionScope(
                groupId: selectedGroupId,
              );
              final Map<String, dynamic> response = hasScope
                  ? await FileManageAPIService.getSigners(
                      token: token,
                      keyword: keyword.isEmpty ? null : keyword,
                      groupId: selectedGroupId,
                      versionId: versionId,
                      limit: pageSize,
                      offset: 0,
                    )
                  : <String, dynamic>{'total': 0, 'items': <dynamic>[]};
              if (!sheetContext.mounted) return;

              setStateFn(() {
                currentGroups = nextGroups;
                users = (response['items'] as List<dynamic>)
                    .map((dynamic item) => Map<String, dynamic>.from(
                        item as Map<dynamic, dynamic>))
                    .toList();
                total = _toInt(response['total']) ?? users.length;
                offset = users.length;
                isLoadingGroups = false;
                isLoadingUsers = false;
              });
            } catch (error) {
              if (!sheetContext.mounted) return;
              setStateFn(() {
                isLoadingGroups = false;
                isLoadingUsers = false;
              });
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(
                    content: Text('Failed to load signer filters: $error')),
              );
            }
          }

          return StatefulBuilder(
            builder:
                (BuildContext ctx, void Function(void Function()) setStateFn) {
              final bool hasScope = hasSignerSelectionScope(
                groupId: selectedGroupId,
              );
              final bool canLoadMore =
                  hasScope && !isLoadingMore && users.length < total;

              return FractionallySizedBox(
                heightFactor: 0.88,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: SafeArea(
                    child: Column(
                      children: <Widget>[
                        const SizedBox(height: 8),
                        Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(ctx).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  'Select signer',
                                  style: Theme.of(ctx).textTheme.titleMedium,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  setStateFn(() {
                                    keyword = initialKeyword?.trim() ?? '';
                                    searchCtl.text = keyword;
                                    selectedGroupId = !auth.isSuperAdmin &&
                                            auth.groupId != null &&
                                            currentGroups.any((group) =>
                                                _toInt(group['id']) ==
                                                auth.groupId)
                                        ? auth.groupId
                                        : initialGroupId;
                                  });
                                  unawaited(loadGroupsAndUsers(setStateFn));
                                },
                                child: Text(local?.clearSelection ?? 'Clear'),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: DropdownButtonFormField<int?>(
                            initialValue: selectedGroupId,
                            decoration: InputDecoration(
                              labelText: local?.group ?? 'Group',
                              border: const OutlineInputBorder(),
                            ),
                            items: <DropdownMenuItem<int?>>[
                              DropdownMenuItem<int?>(
                                value: null,
                                child: Text(local?.notSelected ?? 'Select'),
                              ),
                              ...currentGroups.map(
                                (Map<String, dynamic> group) =>
                                    DropdownMenuItem<int?>(
                                  value: _toInt(group['id']),
                                  child: Text(_toCleanString(group['name'])),
                                ),
                              ),
                            ],
                            onChanged: isLoadingGroups
                                ? null
                                : (int? value) {
                                    setStateFn(() => selectedGroupId = value);
                                    unawaited(loadUsers(setStateFn));
                                  },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: TextField(
                            controller: searchCtl,
                            enabled: hasScope,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: hasScope
                                  ? 'Search by username, name, or email'
                                  : 'Select group first',
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (String value) {
                              if (!hasScope) return;
                              if (debounce?.isActive ?? false) {
                                debounce!.cancel();
                              }
                              debounce = Timer(
                                const Duration(milliseconds: 250),
                                () {
                                  if (!ctx.mounted) return;
                                  setStateFn(() => keyword = value.trim());
                                  unawaited(loadUsers(setStateFn));
                                },
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Row(
                            children: <Widget>[
                              Text(
                                buildSignerResultSummary(
                                  isLoading: isLoadingUsers,
                                  loaded: users.length,
                                  total: total,
                                  hasScope: hasScope,
                                ),
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: !hasScope
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'Select group to start loading signers',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                )
                              : isLoadingUsers && users.isEmpty
                                  ? const Center(
                                      child: CircularProgressIndicator())
                                  : users.isEmpty
                                      ? const Center(
                                          child: Padding(
                                            padding: EdgeInsets.all(24),
                                            child: Text(
                                                'No matching members found'),
                                          ),
                                        )
                                      : ListView.separated(
                                          itemCount: users.length +
                                              (canLoadMore ? 1 : 0),
                                          separatorBuilder: (_, __) =>
                                              const Divider(
                                                  height: 1, thickness: .5),
                                          itemBuilder:
                                              (BuildContext _, int index) {
                                            if (index == users.length) {
                                              return Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 12,
                                                ),
                                                child: OutlinedButton(
                                                  onPressed: isLoadingMore
                                                      ? null
                                                      : () => unawaited(
                                                            loadUsers(
                                                              setStateFn,
                                                              append: true,
                                                            ),
                                                          ),
                                                  child: Text(
                                                    isLoadingMore
                                                        ? 'Loading more...'
                                                        : 'Load more',
                                                  ),
                                                ),
                                              );
                                            }

                                            final Map<String, dynamic> user =
                                                users[index];
                                            final List<String> subtitleLines =
                                                buildSignerSubtitleLines(
                                              user,
                                              groupLabel:
                                                  local?.group ?? 'Group',
                                            );

                                            return ListTile(
                                              title: Text(
                                                _toCleanString(
                                                    user['username']),
                                              ),
                                              subtitle: subtitleLines.isEmpty
                                                  ? null
                                                  : Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: subtitleLines
                                                          .map(
                                                            (String line) =>
                                                                Text(
                                                              line,
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                          )
                                                          .toList(),
                                                    ),
                                              onTap: () =>
                                                  Navigator.pop(ctx, user),
                                            );
                                          },
                                        ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load signers: $error')),
        );
      }
      return null;
    }
  }
}
