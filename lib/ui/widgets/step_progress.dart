import 'package:flutter/material.dart';

/// Numbered steps in a card, ticked off as they finish: green when done,
/// blue while working, grey still to come, with a line joining them.
///
/// First-run setup and installing a language both show their progress with
/// this, so the two look the same. They were drawn separately before and had
/// drifted apart in colour and shape.
class StepProgress extends StatelessWidget {
  /// The steps, in order.
  final List<String> titles;

  /// How many steps are finished. The one after them is the one working.
  final int completed;

  /// Everything is finished, so no step is working.
  final bool finished;

  /// What the working step is doing.
  final String? status;

  /// How far the working step has got, where that is known, as 0 to 1.
  final double? fraction;

  /// Why the working step failed, if it did.
  final String? error;

  const StepProgress({
    super.key,
    required this.titles,
    required this.completed,
    this.finished = false,
    this.status,
    this.fraction,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(titles.length, (index) {
          final isDone = finished || completed > index;
          final isActive = !finished && completed == index;
          final isFailed = isActive && error != null;
          final isLast = index == titles.length - 1;

          Color circleColor;
          Widget circleChild;

          if (isFailed) {
            circleColor = Theme.of(context).colorScheme.error;
            circleChild =
                const Icon(Icons.priority_high, size: 14, color: Colors.white);
          } else if (isDone) {
            circleColor = Colors.green;
            circleChild =
                const Icon(Icons.check, size: 14, color: Colors.white);
          } else {
            circleColor = isActive ? Colors.blue : Colors.grey.shade400;
            circleChild = Text(
              '${index + 1}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            );
          }

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: circleColor,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: circleChild,
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: isDone ? Colors.green : Colors.grey.shade300,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 16.0, top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titles[index],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive || isDone
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isActive
                                ? Colors.blue
                                : (isDone
                                    ? Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color
                                    : Theme.of(context).disabledColor),
                          ),
                        ),
                        if (isFailed) ...[
                          const SizedBox(height: 4),
                          Text(
                            error!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ] else if (isActive) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.blue),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  status ?? '',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (fraction != null) ...[
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: fraction,
                              color: Colors.blue,
                              backgroundColor: Colors.grey.shade300,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
