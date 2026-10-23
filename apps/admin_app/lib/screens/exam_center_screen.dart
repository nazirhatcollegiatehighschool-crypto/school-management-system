import 'package:flutter/material.dart';

import 'approvals_screen.dart';
import 'exam_catalog_screen.dart';
import 'exam_dashboard_screen.dart';
import 'promotion_screen.dart';
import 'results_screen.dart';

class ExamCenterScreen extends StatelessWidget {
  const ExamCenterScreen({super.key});

  static const _steps = <({String title, String subtitle, IconData icon, Color color, Widget screen})>[
    (title: 'একাডেমিক সেশন ও পরীক্ষা', subtitle: 'বছর তৈরি, বিষয়ভিত্তিক অগ্রগতি, নম্বর এন্ট্রি খোলা ও পরীক্ষা প্রকাশ', icon: Icons.event_note_rounded, color: Color(0xFF4F46E5), screen: ExamDashboardScreen()),
    (title: 'নম্বর অনুমোদন', subtitle: 'শিক্ষকের জমা দেওয়া নম্বর যাচাই করুন', icon: Icons.fact_check_rounded, color: Color(0xFF0D9488), screen: ApprovalsScreen()),
    (title: 'ফলাফল ও প্রকাশ', subtitle: 'ফলাফল পর্যালোচনা, প্রকাশ ও রিপোর্ট তৈরি', icon: Icons.emoji_events_rounded, color: Color(0xFFB45309), screen: ResultsScreen()),
    (title: 'শ্রেণি উত্তরণ ও SSC Batch', subtitle: 'Class 6–9: Annual ফলাফলে পরের শ্রেণি · Class 10: Test Exam থেকে SSC Batch', icon: Icons.trending_up_rounded, color: Color(0xFF4F46E5), screen: PromotionScreen()),
    (title: 'পরীক্ষার নীতি', subtitle: 'শ্রেণিভিত্তিক পরীক্ষার ধরন, নম্বরের ওজন ও পাসের নিয়ম', icon: Icons.tune_rounded, color: Color(0xFF7C3AED), screen: ExamCatalogScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('স্কুলের পরীক্ষা · Class 6–10')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(colors: [Color(0xFF334FE8), Color(0xFF7041D8)]),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('স্কুলের নিজস্ব পরীক্ষার কার্যপ্রবাহ', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              SizedBox(height: 6),
              Text('Class 6–10 · সেশন তৈরি → নম্বর সংগ্রহ → যাচাই → ফলাফল প্রকাশ → শ্রেণি উত্তরণ / SSC Batch', style: TextStyle(color: Colors.white70, height: 1.45)),
            ]),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _steps.length; i++) ...[
            _StepCard(step: _steps[i], number: i + 1),
            if (i != _steps.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final ({String title, String subtitle, IconData icon, Color color, Widget screen}) step;
  final int number;
  const _StepCard({required this.step, required this.number});

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.black.withValues(alpha: .06))),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          leading: CircleAvatar(backgroundColor: step.color.withValues(alpha: .10), child: Icon(step.icon, color: step.color)),
          title: Text('$number. ${step.title}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(step.subtitle)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => step.screen)),
        ),
      );
}
