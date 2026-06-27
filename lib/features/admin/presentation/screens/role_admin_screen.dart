import 'package:flutter/material.dart';

import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../domain/admin_role_definition.dart';

class RoleAdminScreen extends StatefulWidget {
  const RoleAdminScreen({super.key});

  @override
  State<RoleAdminScreen> createState() => _RoleAdminScreenState();
}

class _RoleAdminScreenState extends State<RoleAdminScreen> {
  final _repository = AuthRepository(ApiClient());
  List<AdminRoleDefinition> _roles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final roles = await _repository.listAdminRoles();
      if (!mounted) return;
      setState(() => _roles = roles);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientHeader(title: 'Quản lý vai trò', showBack: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AppResponsiveContent(
              padding: EdgeInsets.zero,
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: AppLayoutTokens.pagePaddingFor(
                    MediaQuery.sizeOf(context).width,
                  ),
                  itemCount: _roles.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppLayoutTokens.cardGap),
                  itemBuilder: (context, index) {
                    final role = _roles[index];
                    return _RoleCard(role: role);
                  },
                ),
              ),
            ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final AdminRoleDefinition role;

  const _RoleCard({required this.role});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: role.color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(role.icon, color: role.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    role.description.isEmpty ? role.value : role.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.lock_outline, size: 20),
          ],
        ),
      ),
    );
  }
}
