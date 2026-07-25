import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// TODO: after deploying the API (Task 2) to Render, replace this with the
// public URL, e.g. "https://africa-education-api.onrender.com"
const String kApiBaseUrl = "http://127.0.0.1:8000";

const Color kBrandPrimary = Color(0xFF1F7A5C);
const Color kBrandSecondary = Color(0xFFE8A33D);

void main() {
  runApp(const MissionApp());
}

class MissionApp extends StatelessWidget {
  const MissionApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: kBrandPrimary,
      secondary: kBrandSecondary,
    );

    return MaterialApp(
      title: 'Education Access Predictor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7F6),
        textTheme: Typography.blackMountainView.apply(
          bodyColor: const Color(0xFF1B2420),
          displayColor: const Color(0xFF1B2420),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: kBrandPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: const PredictionPage(),
    );
  }
}

class _FieldSpec {
  final String key;
  final String label;
  final String hint;
  final double min;
  final double max;
  final bool isInt;
  final IconData icon;

  const _FieldSpec({
    required this.key,
    required this.label,
    required this.hint,
    required this.min,
    required this.max,
    required this.icon,
    this.isInt = false,
  });
}

class _Section {
  final String title;
  final IconData icon;
  final List<_FieldSpec> fields;

  const _Section({required this.title, required this.icon, required this.fields});
}

const List<_Section> _sections = [
  _Section(
    title: 'Country & Timeframe',
    icon: Icons.public_rounded,
    fields: [
      _FieldSpec(key: 'year', label: 'Year', hint: '2000 – 2035', min: 2000, max: 2035, isInt: true, icon: Icons.calendar_month_rounded),
      _FieldSpec(key: 'population_total', label: 'Total population', hint: '50,000 – 200,000,000', min: 50000, max: 200000000, icon: Icons.groups_rounded),
      _FieldSpec(key: 'rural_pop_pct', label: 'Rural population (%)', hint: '0 – 100', min: 0, max: 100, icon: Icons.terrain_rounded),
    ],
  ),
  _Section(
    title: 'Economy',
    icon: Icons.trending_up_rounded,
    fields: [
      _FieldSpec(key: 'gdp_per_capita_usd', label: 'GDP per capita (US\$)', hint: '100 – 20,000', min: 100, max: 20000, icon: Icons.attach_money_rounded),
      _FieldSpec(key: 'unemployment_pct', label: 'Unemployment (%)', hint: '0 – 40', min: 0, max: 40, icon: Icons.work_off_rounded),
      _FieldSpec(key: 'gov_edu_exp_pct_gdp', label: 'Gov. education spend (% of GDP)', hint: '0 – 15', min: 0, max: 15, icon: Icons.school_rounded),
    ],
  ),
  _Section(
    title: 'Health & Connectivity',
    icon: Icons.favorite_rounded,
    fields: [
      _FieldSpec(key: 'under5_mortality_per1000', label: 'Under-5 mortality (per 1,000)', hint: '0 – 500', min: 0, max: 500, icon: Icons.child_care_rounded),
      _FieldSpec(key: 'life_expectancy_years', label: 'Life expectancy (years)', hint: '10 – 85', min: 10, max: 85, icon: Icons.monitor_heart_rounded),
      _FieldSpec(key: 'health_exp_per_capita_usd', label: 'Health spend per capita (US\$)', hint: '0 – 800', min: 0, max: 800, icon: Icons.local_hospital_rounded),
      _FieldSpec(key: 'internet_users_pct', label: 'Internet users (%)', hint: '0 – 100', min: 0, max: 100, icon: Icons.wifi_rounded),
    ],
  ),
];

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

enum _ResultState { idle, success, error }

class _PredictionPageState extends State<PredictionPage> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  String _region = 'Sub-Saharan Africa';

  bool _loading = false;
  _ResultState _resultState = _ResultState.idle;
  String? _resultValue;
  String? _resultSubtitle;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    for (final section in _sections) {
      for (final f in section.fields) {
        _controllers[f.key] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _numericValidator(_FieldSpec spec, String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      return 'Enter a number';
    }
    if (parsed < spec.min || parsed > spec.max) {
      return 'Must be ${spec.isInt ? spec.min.toInt() : spec.min} – ${spec.isInt ? spec.max.toInt() : spec.max}';
    }
    return null;
  }

  Future<void> _predict() async {
    setState(() {
      _resultState = _ResultState.idle;
      _errorText = null;
    });

    if (!_formKey.currentState!.validate()) {
      setState(() {
        _resultState = _ResultState.error;
        _errorText = 'Please fix the highlighted fields before predicting.';
      });
      return;
    }

    setState(() => _loading = true);

    final body = <String, dynamic>{
      'year': int.parse(_controllers['year']!.text.trim()),
      'gdp_per_capita_usd': double.parse(_controllers['gdp_per_capita_usd']!.text.trim()),
      'gov_edu_exp_pct_gdp': double.parse(_controllers['gov_edu_exp_pct_gdp']!.text.trim()),
      'under5_mortality_per1000': double.parse(_controllers['under5_mortality_per1000']!.text.trim()),
      'rural_pop_pct': double.parse(_controllers['rural_pop_pct']!.text.trim()),
      'health_exp_per_capita_usd': double.parse(_controllers['health_exp_per_capita_usd']!.text.trim()),
      'internet_users_pct': double.parse(_controllers['internet_users_pct']!.text.trim()),
      'unemployment_pct': double.parse(_controllers['unemployment_pct']!.text.trim()),
      'life_expectancy_years': double.parse(_controllers['life_expectancy_years']!.text.trim()),
      'population_total': double.parse(_controllers['population_total']!.text.trim()),
      'region': _region,
    };

    try {
      final response = await http
          .post(
            Uri.parse('$kApiBaseUrl/predict'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final pct = data['predicted_out_of_school_pct'];
        final modelUsed = data['model_used'];
        setState(() {
          _resultState = _ResultState.success;
          _resultValue = '$pct%';
          _resultSubtitle = 'Predicted out-of-school rate  ·  model: $modelUsed';
        });
      } else {
        setState(() {
          _resultState = _ResultState.error;
          _errorText = _extractErrorMessage(response.body);
        });
      }
    } catch (e) {
      setState(() {
        _resultState = _ResultState.error;
        _errorText = 'Could not reach the prediction API: $e';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  String _extractErrorMessage(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      final detail = decoded['detail'];
      if (detail is String) return detail;
      if (detail is List) {
        return detail
            .map((d) => '${(d['loc'] as List?)?.last ?? ''}: ${d['msg'] ?? ''}')
            .join('\n');
      }
      return responseBody;
    } catch (_) {
      return responseBody;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 148,
            backgroundColor: kBrandPrimary,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16, right: 20),
              title: const Text(
                'Education Access Predictor',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kBrandPrimary, Color(0xFF14503B)],
                  ),
                ),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 4),
                    child: Icon(Icons.auto_graph_rounded, size: 96, color: Colors.white.withValues(alpha: 0.12)),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _MissionBanner(),
                        const SizedBox(height: 20),
                        ..._sections.map(
                          (section) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _SectionCard(
                              section: section,
                              controllers: _controllers,
                              validator: _numericValidator,
                            ),
                          ),
                        ),
                        _SectionCard.custom(
                          title: 'Region',
                          icon: Icons.map_rounded,
                          child: DropdownButtonFormField<String>(
                            initialValue: _region,
                            decoration: const InputDecoration(
                              labelText: 'World Bank region grouping',
                              prefixIcon: Icon(Icons.flag_rounded),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Sub-Saharan Africa', child: Text('Sub-Saharan Africa')),
                              DropdownMenuItem(value: 'MENA', child: Text('MENA (North Africa)')),
                            ],
                            onChanged: (v) => setState(() => _region = v ?? _region),
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _loading ? null : _predict,
                          icon: _loading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                )
                              : const Icon(Icons.insights_rounded),
                          label: Text(_loading ? 'Predicting…' : 'Predict'),
                        ),
                        const SizedBox(height: 20),
                        _ResultCard(
                          state: _resultState,
                          value: _resultValue,
                          subtitle: _resultSubtitle,
                          errorText: _errorText,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionBanner extends StatelessWidget {
  const _MissionBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kBrandSecondary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBrandSecondary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.volunteer_activism_rounded, color: kBrandSecondary),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Predicts the percentage of primary-school-age children who are out '
              'of school for a given African country-year, to help target '
              'education and family-support programs for vulnerable children.',
              style: TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF4A4038)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final _Section? section;
  final Map<String, TextEditingController>? controllers;
  final String? Function(_FieldSpec, String?)? validator;
  final String? title;
  final IconData? icon;
  final Widget? child;

  const _SectionCard({required this.section, required this.controllers, required this.validator})
      : title = null,
        icon = null,
        child = null;

  const _SectionCard.custom({required this.title, required this.icon, required this.child})
      : section = null,
        controllers = null,
        validator = null;

  @override
  Widget build(BuildContext context) {
    final headerTitle = section?.title ?? title!;
    final headerIcon = section?.icon ?? icon!;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(headerIcon, size: 20, color: kBrandPrimary),
              const SizedBox(width: 8),
              Text(
                headerTitle,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kBrandPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ?child,
          if (section != null)
            ...section!.fields.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: controllers![f.key],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: f.label,
                    hintText: f.hint,
                    prefixIcon: Icon(f.icon, size: 20),
                  ),
                  validator: (v) => validator!(f, v),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final _ResultState state;
  final String? value;
  final String? subtitle;
  final String? errorText;

  const _ResultCard({required this.state, this.value, this.subtitle, this.errorText});

  @override
  Widget build(BuildContext context) {
    final isError = state == _ResultState.error;
    final isSuccess = state == _ResultState.success;

    final Color accent = isError ? const Color(0xFFC0392B) : (isSuccess ? kBrandPrimary : Colors.grey.shade500);
    final Color background = isError
        ? const Color(0xFFFDECEA)
        : (isSuccess ? kBrandPrimary.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.06));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : (isSuccess ? Icons.check_circle_rounded : Icons.query_stats_rounded),
            color: accent,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isSuccess) ...[
                  Text(
                    value ?? '',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: accent),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle ?? '', style: const TextStyle(fontSize: 13, color: Color(0xFF4A4A4A))),
                ] else if (isError) ...[
                  Text(
                    errorText ?? 'Something went wrong.',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accent),
                  ),
                ] else ...[
                  const Text(
                    'Fill in the fields above and press Predict to see a result here.',
                    style: TextStyle(fontSize: 14, color: Color(0xFF6B6B6B)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
