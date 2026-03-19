import 'package:flutter/material.dart';
import 'package:phone_ide/editor/autocomplete_data.dart';

class AutocompleteDropdown extends StatelessWidget {
  const AutocompleteDropdown({
    super.key,
    required this.left,
    required this.top,
    required this.width,
    required this.maxHeight,
    required this.itemHeight,
    required this.suggestions,
    required this.highlightedIndex,
    required this.showKeyboardFocusBorder,
    required this.displayLabelBuilder,
    required this.onSuggestionTap,
    required this.onSuggestionTapDown,
    required this.onSuggestionTapCancel,
  });

  final double left;
  final double top;
  final double width;
  final double maxHeight;
  final double itemHeight;
  final List<AutocompleteSuggestion> suggestions;
  final int highlightedIndex;
  final bool showKeyboardFocusBorder;
  final String Function(AutocompleteSuggestion suggestion) displayLabelBuilder;
  final ValueChanged<AutocompleteSuggestion> onSuggestionTap;
  final ValueChanged<int> onSuggestionTapDown;
  final VoidCallback onSuggestionTapCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF2B2B2B),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: showKeyboardFocusBorder
                      ? const Color(0xFF4EA1FF)
                      : const Color(0xFF3C3F41),
                  width: showKeyboardFocusBorder ? 1.2 : 1,
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x77000000),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: Color(0xFF3A3C3E),
                  ),
                  itemBuilder: (_, index) {
                    final AutocompleteSuggestion suggestion =
                        suggestions[index];
                    final String displayLabel = displayLabelBuilder(suggestion);
                    final bool isSelected = index == highlightedIndex;
                    return Material(
                      color: isSelected
                          ? const Color(0xFF0B4F7D)
                          : Colors.transparent,
                      child: InkWell(
                        onTapDown: (_) => onSuggestionTapDown(index),
                        onTapCancel: onSuggestionTapCancel,
                        onTap: () => onSuggestionTap(suggestion),
                        splashColor: const Color(0x33399CE8),
                        highlightColor: const Color(0x222A5F8A),
                        child: SizedBox(
                          height: itemHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            child: Row(
                              children: [
                                if (suggestion.previewColor != null)
                                  Container(
                                    width: 10,
                                    height: 10,
                                    margin: const EdgeInsets.only(right: 10),
                                    decoration: BoxDecoration(
                                      color: suggestion.previewColor,
                                      borderRadius: BorderRadius.circular(2),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.25),
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    width: 10,
                                    height: 10,
                                    margin: const EdgeInsets.only(right: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4A5460),
                                      borderRadius: BorderRadius.circular(2),
                                      border: Border.all(
                                        color: const Color(0xFF6B7682),
                                        width: 0.8,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    displayLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isSelected
                                          ? const Color(0xFFEAF4FF)
                                          : const Color(0xFFD4DCE6),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
