import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../util/icons.dart';
import 'widgets.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Categories'),
            bottom: const TabBar(tabs: [
              Tab(text: 'Expenses'),
              Tab(text: 'Income'),
            ]),
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Add category',
            onPressed: () {
              final idx = DefaultTabController.of(context).index;
              editCategory(context,
                  kind: idx == 0 ? TxType.expense : TxType.income);
            },
            child: const Icon(Icons.add),
          ),
          body: const TabBarView(children: [
            _CategoryList(kind: TxType.expense),
            _CategoryList(kind: TxType.income),
          ]),
        );
      }),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.kind});

  final TxType kind;

  @override
  Widget build(BuildContext context) {
    final groups = groupCategories(AppScope.of(context).categoriesOf(kind));
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final g in groups)
          ExpansionTile(
            initiallyExpanded: groups.length <= 3,
            title: Text(g.key,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${g.value.length} categories'),
            children: [
              for (final c in g.value)
                ListTile(
                  leading: CategoryAvatar(category: c),
                  title: Text(c.name),
                  onTap: () => editCategory(context, kind: kind, category: c),
                ),
            ],
          ),
      ],
    );
  }
}

Future<void> editCategory(BuildContext context,
    {required TxType kind, Category? category}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _CategoryForm(kind: kind, category: category),
    ),
  );
}

class _CategoryForm extends StatefulWidget {
  const _CategoryForm({required this.kind, this.category});

  final TxType kind;
  final Category? category;

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  late final TextEditingController _name;
  String _group = '';
  late String _icon;
  late int _color;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category?.name ?? '');
    _group = widget.category?.group ?? '';
    _icon = widget.category?.icon ?? 'other';
    _color = widget.category?.color ?? kCategoryColors[5];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await AppScope.read(context).saveCategory(Category(
      id: widget.category?.id,
      name: name,
      group: _group.trim(),
      kind: widget.kind,
      icon: _icon,
      color: _color,
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Delete category?',
        message:
            'Transactions in this category will be kept, without a category.');
    if (!ok || !mounted) return;
    await AppScope.read(context).deleteCategory(widget.category!.id!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Row(
            children: [
              CategoryAvatar(
                  category: Category(
                      name: '', kind: widget.kind, icon: _icon, color: _color)),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: widget.category == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _group),
            optionsBuilder: (v) {
              final all = AppScope.read(context)
                  .categoriesOf(widget.kind)
                  .map((c) => c.group)
                  .where((g) => g.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
              final q = v.text.trim().toLowerCase();
              return q.isEmpty
                  ? all
                  : all.where((g) => g.toLowerCase().contains(q));
            },
            onSelected: (v) => _group = v,
            fieldViewBuilder: (context, controller, focus, _) => TextField(
              controller: controller,
              focusNode: focus,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Group',
                hintText: 'e.g. Food & Dining',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _group = v,
            ),
          ),
          const SizedBox(height: 16),
          const Text('Color'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in kCategoryColors)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(c),
                    child: _color == c
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Icon'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in kCategoryIcons.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => setState(() => _icon = e.key),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: _icon == e.key
                        ? Color(_color).withValues(alpha: 0.25)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    foregroundColor: _icon == e.key
                        ? Color(_color)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    child: Icon(e.value),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              if (widget.category != null)
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              const Spacer(),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}
