import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/arivo_theme.dart';
import '../theme/tokens.g.dart';

/// Same order as the Rive state machine input `state` (see assets/mascot/README.md).
enum AriState { idle, listening, thinking, talking, pointing, warning, excited, offline }

extension AriStateX on AriState {
  String get clip => this == AriState.idle ? 'idle_float' : name;
  bool get loops => this != AriState.pointing && this != AriState.excited;
  double get fps => switch (this) { AriState.talking || AriState.excited => 10, AriState.pointing || AriState.warning => 8, AriState.idle || AriState.offline => 4, _ => 5.33 };
}

/// Global Ari state. Rules keep Ari helpful, not noisy: one bubble per screen visit, auto-dismissed.
class AriController extends Notifier<({AriState state, String? bubble})> {
  Timer? _revert;

  @override
  ({AriState state, String? bubble}) build() => (state: AriState.idle, bubble: null);

  void set(AriState s, {String? bubble, Duration? revertAfter}) {
    _revert?.cancel();
    state = (state: s, bubble: bubble);
    if (revertAfter != null) {
      _revert = Timer(revertAfter, () => state = (state: AriState.idle, bubble: null));
    }
  }

  void say(String text, {AriState as = AriState.talking}) => set(as, bubble: text, revertAfter: const Duration(seconds: 6));
  void clearBubble() => state = (state: state.state, bubble: null);
}

final ariProvider = NotifierProvider<AriController, ({AriState state, String? bubble})>(AriController.new);

/// Sprite-sheet renderer (4×4 frames, 256px cells) — cheap enough for the always-visible Guide button.
class AriSprite extends StatefulWidget {
  const AriSprite({super.key, required this.state, this.size = 64});
  final AriState state;
  final double size;

  @override
  State<AriSprite> createState() => _AriSpriteState();
}

class _AriSpriteState extends State<AriSprite> with SingleTickerProviderStateMixin {
  static final Map<AriState, Future<ui.Image>> _cache = {};
  late final AnimationController _ticker = AnimationController(vsync: this, duration: const Duration(seconds: 3));
  ui.Image? _image;
  int _frame = 0;

  Future<ui.Image> _load(AriState s) => _cache.putIfAbsent(s, () async {
        final data = await rootBundle.load('assets/mascot/sprites/ari_${s.clip}.webp');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        return (await codec.getNextFrame()).image;
      });

  @override
  void initState() {
    super.initState();
    _ticker.addListener(_tick);
    _swap();
  }

  @override
  void didUpdateWidget(AriSprite old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _swap();
  }

  Future<void> _swap() async {
    final img = await _load(widget.state);
    if (!mounted) return;
    setState(() {
      _image = img;
      _frame = 0;
    });
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _ticker.stop();
      return;
    }
    _ticker
      ..duration = Duration(milliseconds: (16 / widget.state.fps * 1000).round())
      ..reset();
    widget.state.loops ? _ticker.repeat() : _ticker.forward();
  }

  void _tick() {
    final f = (_ticker.value * 16).floor().clamp(0, 15);
    if (f != _frame) setState(() => _frame = f);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Ari, your Arivo guide — ${widget.state.name}',
      image: true,
      child: SizedBox.square(dimension: widget.size, child: _image == null ? null : CustomPaint(painter: _SpritePainter(_image!, _frame))),
    );
  }
}

class _SpritePainter extends CustomPainter {
  _SpritePainter(this.image, this.frame);
  final ui.Image image;
  final int frame;
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 256.0;
    final src = Rect.fromLTWH((frame % 4) * cell, (frame ~/ 4) * cell, cell, cell);
    canvas.drawImageRect(image, src, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(covariant _SpritePainter o) => o.frame != frame || o.image != image;
}

/// Hero moments (onboarding, Story, Rescue, celebrations): the real 3D Ari with its glTF clips.
class Ari3D extends StatefulWidget {
  const Ari3D({super.key, required this.state, this.height = 280});
  final AriState state;
  final double height;
  @override
  State<Ari3D> createState() => _Ari3DState();
}

class _Ari3DState extends State<Ari3D> {
  final _controller = Flutter3DController();
  bool _loaded = false;

  @override
  void didUpdateWidget(Ari3D old) {
    super.didUpdateWidget(old);
    if (_loaded && old.state != widget.state) _play();
  }

  void _play() => _controller.playAnimation(animationName: widget.state.clip, loopCount: widget.state.loops ? 0 : 1);

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    return SizedBox(
      height: widget.height,
      child: Stack(alignment: Alignment.center, children: [
        if (!_loaded) Image.asset('assets/mascot/posters/poster_idle.webp', height: widget.height * 0.9, semanticLabel: 'Ari'),
        Flutter3DViewer(
          src: 'assets/mascot/ari_explorer.glb',
          controller: _controller,
          enableTouch: !kIsWeb || true,
          progressBarColor: Colors.transparent,
          onLoad: (_) {
            setState(() => _loaded = true);
            _controller.setCameraOrbit(20, 80, 5.4);
            if (!reduce) _play();
          },
        ),
      ]),
    );
  }
}

/// The floating Guide button (60 dp, bottom-right). Tap: Guide sheet. Long-press: voice.
class GuideFab extends ConsumerWidget {
  const GuideFab({super.key, required this.onTap, this.onLongPress});
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ari = ref.watch(ariProvider);
    final p = context.palette;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      AnimatedSwitcher(
        duration: ArivoMotion.base,
        child: ari.bubble == null
            ? const SizedBox.shrink()
            : GestureDetector(
                onTap: () => ref.read(ariProvider.notifier).clearBubble(),
                child: Container(
                  key: ValueKey(ari.bubble),
                  constraints: const BoxConstraints(maxWidth: 260),
                  margin: const EdgeInsets.only(bottom: ArivoSpace.s2),
                  padding: const EdgeInsets.symmetric(horizontal: ArivoSpace.s3, vertical: ArivoSpace.s2),
                  decoration: BoxDecoration(color: ArivoColors.ink800, borderRadius: BorderRadius.circular(ArivoRadius.s), boxShadow: ArivoElevation.raised),
                  child: Text(ari.bubble!, style: ArivoText.of(ArivoPalette.ink).bodyM),
                ),
              ),
      ),
      Semantics(
        button: true,
        label: 'Ask Ari. Long press to talk.',
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            width: ArivoSize.fab,
            height: ArivoSize.fab,
            decoration: BoxDecoration(
              color: p.voltSoft,
              shape: BoxShape.circle,
              boxShadow: ArivoElevation.raised,
              border: Border.all(color: ari.state == AriState.listening ? p.lantern : p.volt, width: 2.5),
            ),
            child: ClipOval(child: Transform.scale(scale: 1.25, child: AriSprite(state: ari.state, size: ArivoSize.fab))),
          ),
        ),
      ),
    ]);
  }
}
