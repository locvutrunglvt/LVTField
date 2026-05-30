// Team Management Service
// Author: Lộc Vũ Trung

import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'dart:math';

/// Team data model
class TeamInfo {
  final String id;
  final String name;
  final String org;
  final String code;
  final String ownerId;
  final DateTime created;
  
  TeamInfo({required this.id, required this.name, required this.org, required this.code, required this.ownerId, required this.created});
  
  factory TeamInfo.fromRecord(RecordModel r) => TeamInfo(
    id: r.id,
    name: r.getStringValue('name'),
    org: r.getStringValue('org'),
    code: r.getStringValue('code'),
    ownerId: r.getStringValue('owner'),
    created: DateTime.tryParse(r.getStringValue('created')) ?? DateTime.now(),
  );
}

/// Team member data model
class TeamMember {
  final String id;
  final String teamId;
  final String userId;
  final String role; // 'leader' or 'member'
  final bool isActive;
  String? userName;
  String? userEmail;
  
  TeamMember({required this.id, required this.teamId, required this.userId, required this.role, required this.isActive, this.userName, this.userEmail});
  
  factory TeamMember.fromRecord(RecordModel r) => TeamMember(
    id: r.id,
    teamId: r.getStringValue('team'),
    userId: r.getStringValue('user'),
    role: r.getStringValue('role'),
    isActive: r.getBoolValue('is_active'),
  );
}

class TeamService {
  static const _serverUrl = 'https://lvtfield.lvtcenter.it.com';
  final PocketBase _pb;
  
  TeamService() : _pb = PocketBase(_serverUrl);
  
  PocketBase get pb => _pb;
  bool get isAuthenticated => _pb.authStore.isValid;
  String? get currentUserId => _pb.authStore.record?.id;
  
  /// Login with email/password
  Future<bool> login(String email, String password) async {
    try {
      await _pb.collection('users').authWithPassword(email, password);
      return true;
    } catch (e) {
      debugPrint('TeamService login error: $e');
      return false;
    }
  }
  
  /// Generate unique team code (6 chars uppercase)
  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
  
  /// Create a new team
  Future<TeamInfo?> createTeam(String name, String org) async {
    if (!isAuthenticated) return null;
    try {
      final code = _generateCode();
      final record = await _pb.collection('teams').create(body: {
        'name': name,
        'org': org,
        'code': code,
        'owner': currentUserId,
      });
      // Auto-join as leader
      await _pb.collection('team_members').create(body: {
        'team': record.id,
        'user': currentUserId,
        'role': 'leader',
        'is_active': true,
      });
      return TeamInfo.fromRecord(record);
    } catch (e) {
      debugPrint('TeamService createTeam error: $e');
      return null;
    }
  }
  
  /// Join team by code
  Future<bool> joinTeam(String code) async {
    if (!isAuthenticated) return false;
    try {
      // Find team by code
      final result = await _pb.collection('teams').getList(
        filter: 'code = "$code"',
        perPage: 1,
      );
      if (result.items.isEmpty) return false;
      
      final teamId = result.items.first.id;
      
      // Check if already member
      final existing = await _pb.collection('team_members').getList(
        filter: 'team = "$teamId" && user = "$currentUserId"',
        perPage: 1,
      );
      if (existing.items.isNotEmpty) return true; // already joined
      
      // Join
      await _pb.collection('team_members').create(body: {
        'team': teamId,
        'user': currentUserId,
        'role': 'member',
        'is_active': true,
      });
      return true;
    } catch (e) {
      debugPrint('TeamService joinTeam error: $e');
      return false;
    }
  }
  
  /// Leave team
  Future<bool> leaveTeam(String teamId) async {
    if (!isAuthenticated) return false;
    try {
      final members = await _pb.collection('team_members').getList(
        filter: 'team = "$teamId" && user = "$currentUserId"',
        perPage: 1,
      );
      if (members.items.isNotEmpty) {
        await _pb.collection('team_members').delete(members.items.first.id);
      }
      // Delete live_position
      try {
        final pos = await _pb.collection('live_positions').getList(
          filter: 'team = "$teamId" && user = "$currentUserId"',
          perPage: 1,
        );
        if (pos.items.isNotEmpty) {
          await _pb.collection('live_positions').delete(pos.items.first.id);
        }
      } catch (_) {}
      return true;
    } catch (e) {
      debugPrint('TeamService leaveTeam error: $e');
      return false;
    }
  }
  
  /// Get my teams
  Future<List<TeamInfo>> getMyTeams() async {
    if (!isAuthenticated) return [];
    try {
      final memberships = await _pb.collection('team_members').getList(
        filter: 'user = "$currentUserId"',
        perPage: 50,
      );
      final teamIds = memberships.items.map((m) => m.getStringValue('team')).toSet();
      if (teamIds.isEmpty) return [];
      
      final filter = teamIds.map((id) => 'id = "$id"').join(' || ');
      final teams = await _pb.collection('teams').getList(filter: filter, perPage: 50);
      return teams.items.map((r) => TeamInfo.fromRecord(r)).toList();
    } catch (e) {
      debugPrint('TeamService getMyTeams error: $e');
      return [];
    }
  }
  
  /// Get team members with user info
  Future<List<TeamMember>> getTeamMembers(String teamId) async {
    if (!isAuthenticated) return [];
    try {
      final members = await _pb.collection('team_members').getList(
        filter: 'team = "$teamId"',
        perPage: 50,
      );
      final result = <TeamMember>[];
      for (final m in members.items) {
        final member = TeamMember.fromRecord(m);
        try {
          final user = await _pb.collection('users').getOne(member.userId);
          member.userName = user.getStringValue('name');
          member.userEmail = user.getStringValue('email');
        } catch (_) {}
        result.add(member);
      }
      return result;
    } catch (e) {
      debugPrint('TeamService getTeamMembers error: $e');
      return [];
    }
  }
  
  /// Delete team (owner only)
  Future<bool> deleteTeam(String teamId) async {
    if (!isAuthenticated) return false;
    try {
      await _pb.collection('teams').delete(teamId);
      return true;
    } catch (e) {
      debugPrint('TeamService deleteTeam error: $e');
      return false;
    }
  }
}
