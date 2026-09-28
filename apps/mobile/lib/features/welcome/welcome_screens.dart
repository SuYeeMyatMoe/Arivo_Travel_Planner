import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/destinations.dart';
import '../../core/theme/arivo_theme.dart';
import '../../core/theme/tokens.g.dart';
import '../../core/ui/clean.dart';
import '../../core/ui/primitives.dart';
import '../../state/session.dart';

/// Splash / hero: full-bleed photo, brand, one button.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Scaffold(
      backgroundColor: ArivoColors.ink950,
      body: Stack(fit: StackFit.expand, children: [
        NetPhoto(Photos.hero),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0x11000000), Color(0x22000000), Color(0xCC000000)],
              stops: [0, 0.35, 0.6, 1],
            ),
          ),
        ),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(ArivoSpace.s6, ArivoSpace.s12, ArivoSpace.s6, ArivoSpace.s6),
                child: Column(children: [
                  const Icon(Icons.flight_rounded, color: Colors.white, size: 56),
                  const SizedBox(height: ArivoSpace.s3),
                  Text('Arivo', style: t.displayXL.copyWith(color: Colors.white, fontSize: 40)),
                  const SizedBox(height: ArivoSpace.s1),
                  Text('Your personal AI travel planner', style: t.bodyL.copyWith(color: Colors.white.withValues(alpha: 0.9))),
                  const Spacer(),
                  Text('Plan smarter.\nTravel happier.', textAlign: TextAlign.center, style: t.titleL.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: ArivoSpace.s6),
                  ArivoButton('Get Started', expand: true, onPressed: () => context.go('/welcome/intro')),
                  const SizedBox(height: ArivoSpace.s2),
                  TextButton(
                    onPressed: () => context.go('/signin'),
                    child: Text('I already have an account', style: t.label.copyWith(color: Colors.white)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Three-page introduction with dots.
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});
  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> {
  final _pages = PageController();
  int _index = 0;

  static const _content = [
    ('Plan Your Perfect Trip\nwith AI', 'Personalised itineraries, smart recommendations, and less stress.'),
    ('Tailored to Your Style', 'Suggestions based on your interests, budget and travel style.'),
    ('Everything in One Place', 'Itineraries, bookings, maps, budget and packing — all in one app.'),
  ];

  void _finish() {
    ref.read(sessionProvider.notifier).finishIntro();
    context.go('/signup');
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final last = _index == _content.length - 1;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: p.volt),
          onPressed: () => _index == 0 ? context.go('/welcome') : _pages.previousPage(duration: ArivoMotion.base, curve: ArivoMotion.standardCurve),
        ),
        actions: [if (!last) TextButton(onPressed: _finish, child: Text('Skip', style: t.label.copyWith(color: p.muted)))],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(children: [
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _content.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: ArivoSpace.s6),
                    child: Column(children: [
                      Expanded(child: _Illustration(i)),
                      Text(_content[i].$1, textAlign: TextAlign.center, style: t.displayM),
                      const SizedBox(height: ArivoSpace.s3),
                      Text(_content[i].$2, textAlign: TextAlign.center, style: t.bodyL.copyWith(color: p.muted)),
                      const SizedBox(height: ArivoSpace.s6),
                    ]),
                  ),
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < _content.length; i++)
                  AnimatedContainer(
                    duration: ArivoMotion.base,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(color: i == _index ? p.volt : p.line, borderRadius: BorderRadius.circular(4)),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.all(ArivoSpace.s6),
                child: ArivoButton(
                  last ? 'Get Started' : 'Next',
                  expand: true,
                  onPressed: last ? _finish : () => _pages.nextPage(duration: ArivoMotion.base, curve: ArivoMotion.standardCurve),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Soft circle + icon composition standing in for illustrations; each intro page gets its own.
class _Illustration extends StatelessWidget {
  const _Illustration(this.page);
  final int page;

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    Widget chip(String label, IconData icon, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(ArivoRadius.pill), boxShadow: ArivoElevation.raised),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: c), const SizedBox(width: 6), Text(label, style: t.label)]),
        );
    Widget bubble(IconData icon, Color c) => Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: p.raised, shape: BoxShape.circle, boxShadow: ArivoElevation.raised),
          child: Icon(icon, color: c),
        );
    final core = switch (page) {
      0 => ClipOval(child: Image.asset('assets/mascot/posters/poster_idle.webp', width: 190, height: 190, fit: BoxFit.cover, semanticLabel: 'Ari, your travel guide')),
      1 => ClipOval(child: NetPhoto(Photos.bali, width: 190, height: 190)),
      _ => Icon(Icons.map_rounded, size: 110, color: p.volt),
    };
    return LayoutBuilder(builder: (context, box) {
      final s = box.biggest.shortestSide.clamp(200.0, 300.0);
      return Center(
        child: SizedBox.square(
          dimension: s,
          child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            Container(width: s * 0.92, height: s * 0.92, decoration: BoxDecoration(color: p.voltSoft, shape: BoxShape.circle)),
            core,
            ...switch (page) {
              0 => [
                  Positioned(top: 4, right: 10, child: bubble(Icons.flight_takeoff_rounded, p.volt)),
                  Positioned(bottom: 10, left: 0, child: bubble(Icons.place_rounded, p.emberText)),
                  Positioned(bottom: 30, right: 0, child: bubble(Icons.auto_awesome_rounded, p.lanternText)),
                ],
              1 => [
                  Positioned(top: 10, left: 0, child: chip('Adventure', Icons.terrain_rounded, const Color(0xFF10B981))),
                  Positioned(top: 30, right: -6, child: chip('Culture', Icons.temple_buddhist_outlined, p.volt)),
                  Positioned(bottom: 40, right: -10, child: chip('Relaxation', Icons.spa_outlined, p.lanternText)),
                  Positioned(bottom: 6, left: 10, child: chip('Food', Icons.ramen_dining_outlined, p.emberText)),
                ],
              _ => [
                  Positioned(top: 8, left: 10, child: bubble(Icons.flight_rounded, p.volt)),
                  Positioned(top: 8, right: 10, child: bubble(Icons.calendar_month_rounded, p.volt)),
                  Positioned(bottom: 8, left: 10, child: bubble(Icons.hotel_rounded, p.lanternText)),
                  Positioned(bottom: 8, right: 10, child: bubble(Icons.account_balance_wallet_rounded, const Color(0xFF10B981))),
                ],
            },
          ]),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------------------------------------------- Auth

/// Create Account / Sign In. Local profile only for now: no password leaves the device and nothing is verified.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, required this.signUp});
  final bool signUp;
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _email = TextEditingController(), _password = TextEditingController();
  bool _hide = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _done({required String email, String? name}) {
    ref.read(sessionProvider.notifier).signIn(email: email, name: name);
    context.go(widget.signUp ? '/setup/interests' : '/home');
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    _done(email: _email.text.trim(), name: widget.signUp ? _name.text.trim() : null);
  }

  void _social(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$provider sign-in isn't connected yet — you're signed in on this device.")));
    _done(email: 'traveller@arivo.app', name: ref.read(sessionProvider).name ?? 'Traveller');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette, t = context.type;
    final up = widget.signUp;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Back', icon: Icon(Icons.arrow_back_rounded, color: p.volt), onPressed: () => context.go('/welcome')),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.fromLTRB(ArivoSpace.s6, ArivoSpace.s2, ArivoSpace.s6, ArivoSpace.s6), children: [
                Text(up ? 'Create Account' : 'Sign In', style: t.displayL),
                const SizedBox(height: ArivoSpace.s2),
                Text(up ? 'Join Arivo and start exploring.' : 'Welcome back!\nSign in to continue your journey.', style: t.bodyM.copyWith(color: p.muted)),
                const SizedBox(height: ArivoSpace.s6),
                if (up) ...[
                  _SocialButton(label: 'Continue with Google', icon: Icons.g_mobiledata_rounded, onTap: () => _social('Google')),
                  const SizedBox(height: ArivoSpace.s3),
                  _SocialButton(label: 'Continue with Apple', icon: Icons.apple_rounded, onTap: () => _social('Apple')),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: ArivoSpace.s4),
                    child: Row(children: [
                      const Expanded(child: Divider()),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: ArivoSpace.s3), child: Text('or', style: t.caption)),
                      const Expanded(child: Divider()),
                    ]),
                  ),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(hintText: 'Name'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Tell us what to call you' : null,
                  ),
                  const SizedBox(height: ArivoSpace.s3),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(hintText: 'Email'),
                  validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
                ),
                const SizedBox(height: ArivoSpace.s3),
                TextFormField(
                  controller: _password,
                  obscureText: _hide,
                  autofillHints: [up ? AutofillHints.newPassword : AutofillHints.password],
                  decoration: InputDecoration(
                    hintText: 'Password',
                    suffixIcon: IconButton(
                      tooltip: _hide ? 'Show password' : 'Hide password',
                      icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: p.muted),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                  validator: (v) => (v ?? '').length < 6 ? 'At least 6 characters' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (!up)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Accounts are stored on this device for now, so there is nothing to reset yet.'))),
                      child: Text('Forgot Password?', style: t.label.copyWith(color: p.voltText)),
                    ),
                  ),
                SizedBox(height: up ? ArivoSpace.s5 : ArivoSpace.s4),
                ArivoButton(up ? 'Sign Up' : 'Sign In', expand: true, onPressed: _submit),
                const SizedBox(height: ArivoSpace.s4),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(up ? 'Already have an account?' : "Don't have an account?", style: t.bodyM.copyWith(color: p.muted)),
                  TextButton(
                    onPressed: () => context.go(up ? '/signin' : '/signup'),
                    child: Text(up ? 'Sign In' : 'Sign Up', style: t.label.copyWith(color: p.voltText)),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 26, color: p.text),
      label: Text(label, style: context.type.label.copyWith(fontSize: 15)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ArivoRadius.s)),
      ),
    );
  }
}
