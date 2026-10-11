import 'package:flutter/material.dart';
import 'package:legado_md3/ui/book/knowledge/character_list_screen.dart';

class CharacterDetailScreen extends StatelessWidget {
  final BookCharacter character;
  final String bookName;
  const CharacterDetailScreen({super.key, required this.character, required this.bookName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(character.name)),
      body: ListView(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            color: Color(character.color ?? 0xFF6750A4).withOpacity(0.1),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: Color(character.color ?? 0xFF6750A4),
                  child: Text(character.name.isNotEmpty ? character.name[0] : '?', style: const TextStyle(fontSize: 36, color: Colors.white)),
                ),
                const SizedBox(height: 16),
                Text(character.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                if (character.gender != null) Text(character.gender!, style: TextStyle(color: Colors.grey[600])),
                const SizedBox(height: 8),
                Text('出自: $bookName', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
          ),
          if (character.description != null) _buildSection('简介', [Text(character.description!)]),
          if (character.relations != null && character.relations!.isNotEmpty) _buildSection('关系', [
            Wrap(spacing: 8, runSpacing: 8, children: character.relations!.map((r) => Chip(label: Text(r))).toList()),
          ]),
          if (character.quotes != null && character.quotes!.isNotEmpty) _buildSection('名言', character.quotes!.map((q) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('"$q"', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 15)))).toList()),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }
}
