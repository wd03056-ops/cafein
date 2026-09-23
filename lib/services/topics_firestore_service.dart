import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/topic.dart';

/// Firestore `topics/{id}` + unique index `topic_names/{nameKey}`.
class TopicsFirestoreService {
  TopicsFirestoreService._();
  static final TopicsFirestoreService instance = TopicsFirestoreService._();

  final _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _topics =>
      _firestore.collection('topics');

  CollectionReference<Map<String, dynamic>> get _topicNames =>
      _firestore.collection('topic_names');

  Future<Topic?> getById(String topicId) async {
    final id = topicId.trim();
    if (id.isEmpty) return null;
    final snap = await _topics.doc(id).get();
    if (!snap.exists || snap.data() == null) return null;
    return Topic.fromFirestore(snap.id, snap.data()!);
  }

  Future<Topic?> findByName(String rawName) async {
    final name = normalizeTopicName(rawName);
    if (name.isEmpty) return null;
    final keySnap = await _topicNames.doc(topicNameKey(name)).get();
    if (!keySnap.exists) return null;
    final id = (keySnap.data()?['topicId'] as String?)?.trim();
    if (id == null || id.isEmpty) return null;
    return getById(id);
  }

  List<Topic>? _popularCache;
  DateTime? _popularCacheAt;
  static const _popularCacheTtl = Duration(minutes: 5);

  /// Drop popular/recent pool so next read picks up server usageCount.
  void invalidatePopularCache() {
    _popularCache = null;
    _popularCacheAt = null;
  }

  Future<List<Topic>> popularTopics({int limit = 10}) async {
    final capped = limit.clamp(1, 30);
    final now = DateTime.now();
    if (_popularCache != null &&
        _popularCacheAt != null &&
        now.difference(_popularCacheAt!) < _popularCacheTtl &&
        _popularCache!.length >= capped) {
      return _popularCache!
          .where((t) => t.usageCount > 0)
          .take(capped)
          .toList();
    }

    // Server-side: only topics that currently have posts (usageCount > 0).
    final snap = await _topics
        .where('usageCount', isGreaterThan: 0)
        .orderBy('usageCount', descending: true)
        .limit(30)
        .get();
    _popularCache =
        snap.docs.map((d) => Topic.fromFirestore(d.id, d.data())).toList();
    _popularCacheAt = now;
    return _popularCache!.take(capped).toList();
  }

  Future<List<Topic>> recentTopics({int limit = 10}) async {
    final capped = limit.clamp(1, 30);
    final snap = await _topics
        .orderBy('createdAt', descending: true)
        .limit(40)
        .get();
    return snap.docs
        .map((d) => Topic.fromFirestore(d.id, d.data()))
        .where((t) => t.usageCount > 0)
        .take(capped)
        .toList();
  }

  Future<List<Topic>> searchTopics(String query, {int limit = 12}) async {
    final q = normalizeTopicName(query).toLowerCase();
    if (q.isEmpty) return popularTopics(limit: limit);

    // Reuse cached popular pool (usageCount > 0 only).
    final pool = await popularTopics(limit: 30);
    final matched = pool
        .where((t) => t.name.toLowerCase().contains(q))
        .take(limit)
        .toList();

    if (matched.every((t) => topicNameKey(t.name) != topicNameKey(query))) {
      final keySnap = await _topicNames.doc(topicNameKey(query)).get();
      if (keySnap.exists) {
        final id = (keySnap.data()?['topicId'] as String?)?.trim();
        if (id != null && id.isNotEmpty) {
          final topic = await getById(id);
          // Hide zero-usage topics from browse/search lists.
          if (topic != null &&
              topic.usageCount > 0 &&
              !matched.any((t) => t.id == topic.id)) {
            matched.insert(0, topic);
          }
        }
      }
    }
    return matched.take(limit).toList();
  }

  /// Get or create topic (usageCount starts at 0; increment on post success).
  Future<Topic> ensureTopic(String rawName) async {
    final name = normalizeTopicName(rawName);
    if (name.isEmpty) {
      throw ArgumentError('주제 이름이 비어 있어요.');
    }
    final key = topicNameKey(name);

    try {
      return await _firestore.runTransaction((tx) async {
        final keyRef = _topicNames.doc(key);
        final keySnap = await tx.get(keyRef);

        if (keySnap.exists) {
          final existingId =
              (keySnap.data()?['topicId'] as String?)?.trim() ?? '';
          if (existingId.isEmpty) {
            throw StateError('topic_names/$key missing topicId');
          }
          final topicRef = _topics.doc(existingId);
          final topicSnap = await tx.get(topicRef);
          if (topicSnap.exists && topicSnap.data() != null) {
            return Topic.fromFirestore(topicSnap.id, topicSnap.data()!);
          }
          tx.set(topicRef, {
            'name': name,
            'nameKey': key,
            'usageCount': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return Topic(id: topicRef.id, name: name, usageCount: 0);
        }

        final topicRef = _topics.doc();
        tx.set(topicRef, {
          'name': name,
          'nameKey': key,
          'usageCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(keyRef, {
          'topicId': topicRef.id,
          'name': name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return Topic(id: topicRef.id, name: name, usageCount: 0);
      });
    } catch (e) {
      debugPrint('ensureTopic 실패: $e');
      rethrow;
    }
  }
}
