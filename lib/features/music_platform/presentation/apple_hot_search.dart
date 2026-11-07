import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../data/platform_recommendations.dart';

/// Ranked keywords remain search actions. A compact editorial grid provides
/// scanable ranks without turning words into fabricated playable songs.
class AppleHotSearchBoards extends StatefulWidget {
  const AppleHotSearchBoards({
    required this.boards,
    required this.onSearch,
    super.key,
  });
  final List<PlatformHotSearchBoard> boards;
  final ValueChanged<String> onSearch;
  @override
  State<AppleHotSearchBoards> createState() => _AppleHotSearchBoardsState();
}

class _AppleHotSearchBoardsState extends State<AppleHotSearchBoards> {
  int _board = 0, _page = 0;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final index = _board.clamp(0, widget.boards.length - 1);
    final words = widget.boards[index].keywords;
    final pages = (words.length / 10).ceil();
    final page = pages == 0 ? 0 : _page.clamp(0, pages - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < widget.boards.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 7, bottom: 12),
                  child: Semantics(
                    selected: index == i,
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      minimumSize: const Size(44, 44),
                      color: index == i
                          ? theme.colorScheme.surfaceContainerHigh
                          : theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      onPressed: () => setState(() {
                        _board = i;
                        _page = 0;
                      }),
                      child: Text(
                        widget.boards[i].name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: index == i
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: index == i
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, bounds) {
            final columns = bounds.maxWidth >= 650 ? 3 : 2;
            final width = bounds.maxWidth / columns;
            return Wrap(
              children: [
                for (
                  var i = page * 10;
                  i < words.length && i < (page + 1) * 10;
                  i++
                )
                  SizedBox(
                    width: width,
                    child: Semantics(
                      label: '第${i + 1}名，${words[i]}，搜索',
                      button: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => widget.onSearch(words[i]),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 58),
                          padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 30,
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: i < 3
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  words[i],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.3,
                                    fontWeight: FontWeight.w500,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (pages > 1)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _page = (page + 1) % pages),
              icon: const Icon(CupertinoIcons.arrow_2_circlepath, size: 16),
              label: Text('换一页 · ${page + 1}/$pages'),
            ),
          ),
      ],
    );
  }
}
