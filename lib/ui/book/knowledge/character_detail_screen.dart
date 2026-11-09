/// 由 character_list_screen.dart 拆分还原（历史合并点）。
/// 以 part 形式归属同一库，私有成员互通，外部 import 路径不变。
part of 'character_list_screen.dart';


class CharacterDetailScreen extends StatelessWidget {
  final BookCharacter character;
  final String bookName;
  const CharacterDetailScreen(
      {super.key, required this.character, required this.bookName});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = Color(character.color ?? cs.primary.value);
    return Scaffold(
      appBar: AppBar(title: Text(character.name)),
      body: ListView(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            color: bg.withOpacity(0.1),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: bg,
                  backgroundImage:
                      (character.avatar != null &&
                              character.avatar!.startsWith('http'))
                          ? NetworkImage(character.avatar!)
                          : null,
                  child: (character.avatar == null ||
                          !character.avatar!.startsWith('http'))
                      ? Text(
                          character.name.isNotEmpty ? character.name[0] : '?',
                          style: const TextStyle(
                              fontSize: 36, color: Colors.white))
                      : null,
                ),
                const SizedBox(height: AppSpacing.l),
                Text(character.name,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
                if (character.gender != null)
                  Text(character.gender!,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: AppSpacing.s),
                Text('出自: $bookName',
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
          if (character.description != null)
            _buildSection('简介', [Text(character.description!)]),
          if (character.relations != null &&
              character.relations!.isNotEmpty)
            _buildSection('关系', [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: character.relations!
                    .map((r) => Chip(label: Text(r)))
                    .toList(),
              ),
            ]),
          if (character.quotes != null && character.quotes!.isNotEmpty)
            _buildSection(
                '名言',
                character.quotes!
                    .map((q) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.s),
                          child: Text('"$q"',
                              style: const TextStyle(
                                  fontStyle: FontStyle.italic, fontSize: 15)),
                        ))
                    .toList()),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
        const SizedBox(height: AppSpacing.s),
      ],
    );
  }
}
