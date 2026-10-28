import 'package:flutter/material.dart';
import 'home_page.dart' as home;
import 'settings_page.dart';
import 'dining_hall_detail_page.dart';
import '../widgets/best_hall_banner.dart';

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const home.MainPage()),
            );
          } else if (index == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const SettingsPage()),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.restaurant),
            label: 'Dining Halls',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              // Logo at the top
              Center(
                child: Image.asset(
                  'assets/images/Logo.png',
                  height: 60, // adjust as needed
                ),
              ),
              const SizedBox(height: 16),

              // Search bar
              TextField(
                decoration: InputDecoration(
                  hintText: "Search",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.grey[200],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                ),
              ),
              const SizedBox(height: 16),

              // Top Buttons Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTopButton(Icons.favorite_border, "Favorites"),
                    _buildTopButton(Icons.history, "History"),
                    _buildTopButton(Icons.person_add_alt_1_outlined, "Following"),
                    _buildTopButton(Icons.qr_code_scanner_outlined, "QR"),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Dining hall that best fits the user's restrictions and goal
              const BestHallBanner(),

              // Image banner with text overlay
              //Dining Hall
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DiningHallDetailPage(
                        diningHallName: 'ISR',
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Image.asset(
                        'assets/images/ISR.jpg',
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      Container(
                        height: 150,
                        width: double.infinity,
                        color: Colors.black.withValues(alpha: 0.3),
                        padding: const EdgeInsets.all(16),
                        alignment: Alignment.centerLeft,
                        child: const Text(
                          "ISR",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              //Image banner with text overlay
              //Dining Hall
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DiningHallDetailPage(
                        diningHallName: 'PAR',
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Image.asset(
                        'assets/images/PAR.webp',
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      Container(
                        height: 150,
                        width: double.infinity,
                        color: Colors.black.withValues(alpha: 0.3),
                        padding: const EdgeInsets.all(16),
                        alignment: Alignment.centerLeft,
                        child: const Text(
                          "PAR",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              //Image banner with text overlay
              //Dining Hall
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DiningHallDetailPage(
                        diningHallName: 'LAR',
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Image.asset(
                        'assets/images/Allen.jpg',
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      Container(
                        height: 150,
                        width: double.infinity,
                        color: Colors.black.withValues(alpha: 0.3),
                        padding: const EdgeInsets.all(16),
                        alignment: Alignment.centerLeft,
                        child: const Text(
                          "LAR/Allen",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              //Image banner with text overlay
              //Dining Hall
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DiningHallDetailPage(
                        diningHallName: 'Ikenberry Dining Center',
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Image.asset(
                        'assets/images/Ikenberry.jpg',
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      Container(
                        height: 150,
                        width: double.infinity,
                        color: Colors.black.withValues(alpha: 0.3),
                        padding: const EdgeInsets.all(16),
                        alignment: Alignment.centerLeft,
                        child: const Text(
                          "Ikenberry",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),



            ],
          ),
        ),
      ),
    );
  }

  // Helper widget for top buttons
  static Widget _buildTopButton(IconData icon, String label) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          side: BorderSide(color: Colors.grey[300]!),
        ),
      ),
    );
  }

  // Helper widget for food items
  static Widget _buildFoodItem(String assetName, String name) {
    return Container(
      margin: const EdgeInsets.only(right: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircleAvatar(
            backgroundImage: AssetImage('assets/images/$assetName'),
            radius: 35,
          ),
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for progress bars
  static Widget _buildProgressBar(String label, double current, double goal, String unit) {
    double progress = current / goal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("$label: ${current.toInt()}/${goal.toInt()} $unit"),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey[200],
          color: Colors.blueAccent,
          minHeight: 4,
        ),
      ],
    );
  }
}
