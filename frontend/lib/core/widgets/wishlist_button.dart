import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_state.dart';
import '../../app/api_providers.dart';
import '../../app/providers.dart';
import '../../app/remote_wishlist.dart';
import '../../domain/catalog.dart';
import '../design/tokens.dart';
import 'primitives.dart';

class WishlistButton extends ConsumerWidget {
  const WishlistButton(
    this.product, {
    super.key,
    this.card = false,
    this.enabled = true,
  });
  final Product product;
  final bool card;
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(remoteApiProvider);
    final wishlist = remote ? ref.watch(remoteWishlistProvider) : null;
    final signedIn = ref.watch(accountProvider) != null;
    final saved = remote
        ? wishlist!.items.containsKey(product.id)
        : ref.watch(wishlistProvider).contains(product.id);
    final suffix = card ? ' ${product.name}' : '';
    final tooltip = remote && signedIn && !wishlist!.loaded
        ? 'Tải lại yêu thích$suffix'
        : saved
        ? 'Bỏ yêu thích$suffix'
        : card
        ? 'Yêu thích$suffix'
        : 'Lưu yêu thích';
    Future<void> toggle() async {
      if (!remote) {
        ref.read(wishlistProvider.notifier).toggle(product.id);
        return;
      }
      if (!signedIn) {
        context.go(
          Uri(
            path: '/login',
            queryParameters: {'next': GoRouterState.of(context).uri.toString()},
          ).toString(),
        );
        return;
      }
      try {
        await wishlist!.toggle(product.id);
      } catch (e) {
        if (context.mounted) toast(context, wishlist!.error ?? '$e');
      }
    }

    final icon = Icon(
      saved ? Icons.favorite : Icons.favorite_border,
      size: card ? 20 : 24,
      color: saved ? T.accent : T.ink,
    );
    final disabled = !enabled || remote && (wishlist!.busy || wishlist.loading);
    return card
        ? IconButton.filledTonal(
            tooltip: tooltip,
            onPressed: disabled ? null : toggle,
            icon: icon,
            style: IconButton.styleFrom(
              backgroundColor: T.surface.withValues(alpha: .94),
            ),
          )
        : IconButton(
            tooltip: tooltip,
            onPressed: disabled ? null : toggle,
            icon: icon,
          );
  }
}
