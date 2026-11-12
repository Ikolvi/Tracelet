import 'package:material_ui/material_ui.dart';
import 'package:tracelet_example/issues/archived_issues_tab.dart';
import 'package:tracelet_example/issues/recent_issues_tab.dart';

class IssuesPage extends StatelessWidget {
  const IssuesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Known Issues & Tests'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Recent Issues'),
              Tab(text: 'Archived Issues'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [RecentIssuesTab(), ArchivedIssuesTab()],
        ),
      ),
    );
  }
}
