import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/playlist_config.dart';
import '../models/playlist.dart';
import '../services/xtream_service.dart';

/// EPG Program information
class EpgProgram {
  final String id;
  final String channelId;
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final String? imageUrl;
  final bool isNow;
  final bool isNext;

  EpgProgram({
    required this.id,
    required this.channelId,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    this.imageUrl,
    this.isNow = false,
    this.isNext = false,
  });

  Duration get duration => endTime.difference(startTime);
  
  double get progress {
    if (!isNow) return 0;
    final now = DateTime.now();
    if (now.isBefore(startTime)) return 0;
    if (now.isAfter(endTime)) return 100;
    return ((now.difference(startTime).inSeconds) / duration.inSeconds) * 100;
  }
}

/// EPG Grid View Screen (7 days, 24 hours)
class EpgGridScreen extends ConsumerStatefulWidget {
  final Playlist playlist;

  const EpgGridScreen({
    Key? key,
    required this.playlist,
  }) : super(key: key);

  @override
  ConsumerState<EpgGridScreen> createState() => _EpgGridScreenState();
}

class _EpgGridScreenState extends ConsumerState<EpgGridScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final _horizontalScroll = ScrollController();
  final _verticalScroll = ScrollController();
  Map<String, List<EpgProgram>> _epgData = {};
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEpgData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  Future<void> _loadEpgData() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final service = ref.read(xtreamServiceProvider(widget.playlist));
      final channels = await service.getLiveChannels();

      final epgMap = <String, List<EpgProgram>>{};

      // Load EPG for each channel
      for (final channel in channels) {
        try {
          final epg = await service.getFullEpg(channel.streamId.toString());
          final programs = _parseEpgPrograms(epg, channel.streamId.toString());
          epgMap[channel.streamId.toString()] = programs;
        } catch (e) {
          print('Error loading EPG for ${channel.name}: $e');
          epgMap[channel.streamId.toString()] = [];
        }
      }

      setState(() {
        _epgData = epgMap;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading EPG: $e');
      setState(() => _isLoading = false);
    }
  }

  List<EpgProgram> _parseEpgPrograms(
      Map<String, dynamic> epgData, String channelId) {
    final programs = <EpgProgram>[];
    final now = DateTime.now();

    // Parse EPG data structure
    if (epgData.containsKey('epg_listings')) {
      final listings = epgData['epg_listings'] as List;
      for (final item in listings) {
        try {
          final startStr = item['start'] as String?;
          final endStr = item['end'] as String?;
          final title = item['title'] as String?;
          final desc = item['description'] as String? ?? '';

          if (startStr != null && endStr != null && title != null) {
            final start = _parseEpgTime(startStr);
            final end = _parseEpgTime(endStr);

            programs.add(EpgProgram(
              id: '${channelId}_${start.millisecondsSinceEpoch}',
              channelId: channelId,
              title: title,
              description: desc,
              startTime: start,
              endTime: end,
              isNow: now.isAfter(start) && now.isBefore(end),
              isNext: start.isAfter(now) &&
                  start.difference(now).inMinutes < 60,
            ));
          }
        } catch (e) {
          continue;
        }
      }
    }

    // Sort by start time
    programs.sort((a, b) => a.startTime.compareTo(b.startTime));
    return programs;
  }

  DateTime _parseEpgTime(String timeStr) {
    try {
      // Handle various formats: "12:30", "12:30:00", unix timestamp
      if (timeStr.contains(':')) {
        final parts = timeStr.split(':');
        final hours = int.parse(parts[0]);
        final minutes = int.parse(parts[1]);
        final today = DateTime.now();
        return DateTime(today.year, today.month, today.day, hours, minutes);
      } else {
        return DateTime.fromMillisecondsSinceEpoch(int.parse(timeStr) * 1000);
      }
    } catch (e) {
      return DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EPG Guide'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          onTap: (index) {
            setState(() {
              _selectedDate = DateTime.now().add(Duration(days: index));
            });
          },
          tabs: List.generate(7, (index) {
            final date = DateTime.now().add(Duration(days: index));
            final day = DateFormat('EEE').format(date);
            final dateNum = DateFormat('d').format(date);
            return Tab(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(day, style: const TextStyle(fontSize: 11)),
                  Text(dateNum, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildEpgGrid(),
    );
  }

  Widget _buildEpgGrid() {
    if (_epgData.isEmpty) {
      return const Center(
        child: Text('No EPG data available'),
      );
    }

    final channels = _epgData.keys.toList();

    return Scrollbar(
      controller: _horizontalScroll,
      child: SingleChildScrollView(
        controller: _horizontalScroll,
        scrollDirection: Axis.horizontal,
        child: Column(
          children: [
            // Time headers
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: Colors.grey[700]!),
                          bottom: BorderSide(color: Colors.grey[700]!),
                        ),
                      ),
                    ),
                  ),
                  ...List.generate(24, (hour) {
                    return Container(
                      width: 100,
                      height: 60,
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: Colors.grey[700]!),
                          bottom: BorderSide(color: Colors.grey[700]!),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$hour:00',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),

            // Channel rows
            Expanded(
              child: Scrollbar(
                controller: _verticalScroll,
                child: ListView.builder(
                  controller: _verticalScroll,
                  itemCount: channels.length,
                  itemBuilder: (context, index) {
                    final channelId = channels[index];
                    final programs = _epgData[channelId] ?? [];

                    return _EpgChannelRow(
                      channelId: channelId,
                      programs: programs,
                      onProgramTap: (program) {
                        _showProgramDetail(program);
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProgramDetail(EpgProgram program) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _ProgramDetailSheet(program: program),
    );
  }
}

/// Individual channel row in EPG grid
class _EpgChannelRow extends StatelessWidget {
  final String channelId;
  final List<EpgProgram> programs;
  final Function(EpgProgram) onProgramTap;

  const _EpgChannelRow({
    required this.channelId,
    required this.programs,
    required this.onProgramTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Channel name
        Container(
          width: 150,
          height: 100,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: Colors.grey[700]!),
              bottom: BorderSide(color: Colors.grey[700]!),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              channelId,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ),

        // Programs
        ...programs.map((program) {
          final duration = program.duration.inMinutes;
          final width = (duration / 60 * 100).clamp(40, double.infinity).toDouble();

          return GestureDetector(
            onTap: () => onProgramTap(program),
            child: Container(
              width: width,
              height: 100,
              decoration: BoxDecoration(
                color: program.isNow
                    ? Colors.blue.withOpacity(0.7)
                    : program.isNext
                        ? Colors.purple.withOpacity(0.5)
                        : Colors.grey[800],
                border: Border(
                  right: BorderSide(color: Colors.grey[700]!),
                  bottom: BorderSide(color: Colors.grey[700]!),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Program info
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          program.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${DateFormat('HH:mm').format(program.startTime)} - ${DateFormat('HH:mm').format(program.endTime)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                  ),

                  // Progress bar for now playing
                  if (program.isNow)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(4),
                        ),
                        child: LinearProgressIndicator(
                          value: program.progress / 100,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          valueColor:
                              const AlwaysStoppedAnimation(Colors.red),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Program detail bottom sheet
class _ProgramDetailSheet extends StatelessWidget {
  final EpgProgram program;

  const _ProgramDetailSheet({required this.program});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            program.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                program.isNow ? Icons.play_circle : Icons.schedule,
                color: program.isNow ? Colors.green : Colors.orange,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                '${DateFormat('HH:mm').format(program.startTime)} - ${DateFormat('HH:mm').format(program.endTime)}',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(width: 16),
              Text(
                '${program.duration.inMinutes} min',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            program.description.isEmpty ? 'No description available' : program.description,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Watch Now'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.event),
                label: const Text('Add Reminder'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
