import 'package:flutter/material.dart';
import 'package:medsoft_patient/time_order/time_order_screen.dart';

class BranchSelectionModal extends StatelessWidget {
  final List<DropdownItem> branches;
  final ValueChanged<DropdownItem> onBranchSelected;
  final DropdownItem? currentSelectedBranch;

  final Future<void> Function(String url) launchUrlCallback;

  const BranchSelectionModal({
    super.key,
    required this.branches,
    required this.onBranchSelected,
    this.currentSelectedBranch,
    required this.launchUrlCallback,
  });

  Widget _buildItemChild(DropdownItem item) {
    final bool isBranchWithLogo = item.logoUrl != null && item.logoUrl!.isNotEmpty;
    final bool isBranchUnavailable = isBranchWithLogo && !item.isAvailable;
    final bool isBranchAvailable = isBranchWithLogo && item.isAvailable;

    const double bannerHeight = 220.0;
    final bool isSelected = item.id == currentSelectedBranch?.id;
    final bool isUnavailableBranch = !item.isAvailable;

    return InkWell(
      onTap:
          isUnavailableBranch
              ? null
              : () {
                onBranchSelected(item);
              },
      child: Opacity(
        opacity: isBranchUnavailable ? 0.8 : 1.0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: Container(
            height: bannerHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? Colors.blue.shade700 : Colors.grey.shade300,
                width: isSelected ? 3.0 : 1.0,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColorFiltered(
                  colorFilter:
                      isBranchUnavailable
                          ? const ColorFilter.matrix(<double>[
                            0.2126,
                            0.7152,
                            0.0722,
                            0,
                            0,
                            0.2126,
                            0.7152,
                            0.0722,
                            0,
                            0,
                            0.2126,
                            0.7152,
                            0.0722,
                            0,
                            0,
                            0,
                            0,
                            0,
                            1,
                            0,
                          ])
                          : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                  child: Image.network(
                    item.logoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (context, error, stackTrace) => Container(
                          color: Colors.grey[400],
                          child: const Center(
                            child: Icon(Icons.apartment, color: Colors.white, size: 40),
                          ),
                        ),
                  ),
                ),

                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                    color: Colors.black38,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 4),

                        if ((item.phones != null && item.phones!.isNotEmpty) ||
                            (item.facebook != null && item.facebook!.isNotEmpty))
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (item.phones != null && item.phones!.isNotEmpty)
                                Wrap(
                                  spacing: 8.0,
                                  runSpacing: 4.0,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    const Icon(Icons.phone, color: Colors.white70, size: 14),
                                    ...item.phones!.map(
                                      (phone) => InkWell(
                                        onTap: () => launchUrlCallback('tel:$phone'),
                                        child: Text(
                                          phone,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            decoration: TextDecoration.underline,
                                            decorationColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 8),

                              if (item.facebook != null && item.facebook!.isNotEmpty)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    InkWell(
                                      onTap: () => launchUrlCallback(item.facebook!),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.facebook,
                                            color:
                                                isBranchAvailable
                                                    ? Colors.blueAccent
                                                    : Colors.white,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Facebook Page',
                                            style: TextStyle(
                                              color:
                                                  isBranchAvailable
                                                      ? Colors.blueAccent
                                                      : Colors.white,
                                              fontSize: 14,
                                              decoration: TextDecoration.underline,
                                              decorationColor:
                                                  isBranchAvailable
                                                      ? Colors.blueAccent
                                                      : Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),

                if (isBranchUnavailable)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ОНЛАЙН ҮЗЛЭГИЙН ХУВААРЬ БАЙХГҮЙ',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),

                if (isBranchAvailable)
                  const Positioned(top: 50, right: 50, child: PulsingClickIndicator()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0).copyWith(top: 0),
      child: ListView.builder(
        itemCount: branches.length,
        itemBuilder: (context, index) {
          final item = branches[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: _buildItemChild(item),
          );
        },
      ),
    );
  }
}
