// Copyright 2016 The Vanadium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'package:intl/intl.dart';
import 'package:dlog/dlog.dart' show Table;

import '../mobile/device.dart' show Device;
import '../mobile/device_spec.dart' show DeviceSpec;
import '../util.dart';
import '../globals.dart';

class GroupInfo {
  Map<String, List<Device>> _deviceClusters;
  Map<String, List<DeviceSpec>> _deviceSpecClusters;
  List<String> _deviceClustersOrder;
  List<String> _deviceSpecClustersOrder;

  GroupInfo(
    Map<String, List<Device>> deviceClusters,
    Map<String, List<DeviceSpec>> deviceSpecClusters
  ) {
    _deviceClusters = deviceClusters;
    _deviceSpecClusters = deviceSpecClusters;
    _deviceClustersOrder = new List.from(_deviceClusters.keys);
    _deviceSpecClustersOrder = new List.from(_deviceSpecClusters.keys);
  }

  Map<String, List<Device>> get deviceClusters => _deviceClusters;
  Map<String, List<DeviceSpec>> get deviceSpecClusters => _deviceSpecClusters;
  List<String> get deviceClustersOrder => _deviceClustersOrder;
  List<String> get deviceSpecClustersOrder => _deviceSpecClustersOrder;
}

// -1 indicates that an app-device path can never be covered given the available
// devices.  0 indicates that an app-device path can be covered, but not covered
// yet. (No test script is run under this setting) A positive number indicates
// the number of times an app-device path is hit by some test runs.
const int cannotBeCovered = -1;
const int isNotCovered = 0;
const int oneHit = 1;

class CoverageMatrix {

  CoverageMatrix(this.groupInfo) {
    this.matrix = new List<List<int>>(groupInfo.deviceSpecClusters.length);
    for (int i = 0; i < matrix.length; i++) {
      matrix[i]
        = new List<int>.filled(groupInfo.deviceClusters.length, cannotBeCovered);
    }
  }

  GroupInfo groupInfo;
  // Coverage matrix, where a row indicats an app group and a column
  // indicates a device group
  List<List<int>> matrix;

  void fill(Map<DeviceSpec, Device> match, int value) {
    match.forEach((DeviceSpec spec, Device device) {
      int rowNum = groupInfo.deviceSpecClustersOrder
                              .indexOf(spec.groupKey());
      int colNum = groupInfo.deviceClustersOrder
                              .indexOf(device.groupKey());
      matrix[rowNum][colNum] = value;
    });
  }

  void hit(Map<DeviceSpec, Device> match) {
    match.forEach((DeviceSpec spec, Device device) {
      int rowNum = groupInfo.deviceSpecClustersOrder
                              .indexOf(spec.groupKey());
      int colNum = groupInfo.deviceClustersOrder
                              .indexOf(device.groupKey());
      matrix[rowNum][colNum] += oneHit;
    });
  }

  void union(CoverageMatrix newCoverage) {
    for (int i = 0; i < matrix.length; i++) {
      List<int> row = matrix[i];
      for (int j = 0; j < row.length; j++) {
        if (matrix[i][j] == cannotBeCovered
            &&
            newCoverage.matrix[i][j] == isNotCovered) {
          matrix[i][j] = isNotCovered;
        }
      }
    }
  }

  /// Compute and print the app-device coverage.
  static void computeAndReportCoverage(CoverageMatrix coverageMatrix) {
    if (briefMode) {
      return;
    }
    if (coverageMatrix == null) {
      printError('Coverage matrix is null');
      return;
    }
    int countNumberInCoverageMatrix(List<List<int>> matrix, bool test(int e)) {
      int result = 0;
      matrix.forEach((List<int> row) {
        result += row.where((int element) => test(element)).length;
      });
      return result;
    }
    List<List<int>> matrix = coverageMatrix.matrix;
    int rowNum = matrix.length;
    int colNum = matrix[0].length;
    int totalPathNum = rowNum * colNum;
    int reachableCombinationNum
      = countNumberInCoverageMatrix(matrix, (int e) => e != cannotBeCovered);
    int coveredCombinationNum
      = countNumberInCoverageMatrix(matrix, (int e) => e > isNotCovered);
    StringBuffer scoreReport = new StringBuffer();
    NumberFormat percentFormat = new NumberFormat('%##.0#', 'en_US');
    scoreReport.writeln('App-Device Path Coverage (ADPC) score:');
    double reachableCoverageScore = reachableCombinationNum / totalPathNum;
    scoreReport.writeln(
      'Reachable ADPC score: ${percentFormat.format(reachableCoverageScore)}, '
      'defined by #reachable / #total.'
    );
    double coveredCoverageScore
      = coveredCombinationNum / reachableCombinationNum;
    scoreReport.writeln(
      'Covered ADPC score: ${percentFormat.format(coveredCoverageScore)}, '
      'defined by #covered / #reachable.'
    );
    print(scoreReport.toString());
  }

  static void printLegend() {
    if (briefMode) {
      return;
    }
    StringBuffer legendInfo = new StringBuffer();
    legendInfo.writeln('Meaning of the number in the coverage matrix:');
    legendInfo.writeln(
      '$cannotBeCovered: an app-device path is not reachable '
      'given the connected devices.'
    );
    legendInfo.writeln(
      ' $isNotCovered: an app-device path is reachable but '
      'not covered by any test run.'
    );
    legendInfo.writeln(
      '>$isNotCovered: the number of times an app-device path '
      'is covered by some test runs.'
    );
    print(legendInfo.toString());
  }

  static void printCoverageMatrix(String title, CoverageMatrix coverageMatrix) {
    if (briefMode) {
      return;
    }
    printMatrix(
      title,
      coverageMatrix,
      (int e) {
        if (e == -1) {
          return 'unreachable';
        } else {
          return 'reachable';
        }
      }
    );
  }

  static void printHitmap(String title, CoverageMatrix coverageMatrix) {
    if (briefMode) {
      return;
    }
    printMatrix(
      title,
      coverageMatrix,
      (int e) {
        return '$e';
      }
    );
    printLegend();
    computeAndReportCoverage(coverageMatrix);
  }
}

void printMatrix(String title, CoverageMatrix coverageMatrix, f(int e)) {
  if (coverageMatrix == null) {
    return;
  }
  GroupInfo groupInfo = coverageMatrix.groupInfo;
  List<List<int>> matrix = coverageMatrix.matrix;
  Table prettyMatrix = new Table(1);
  prettyMatrix.columns.add('app key \\ device key');
  prettyMatrix.columns.addAll(groupInfo.deviceClustersOrder);
  int startIndx = beginOfDiff(groupInfo.deviceSpecClustersOrder);
  for (int i = 0; i < matrix.length; i++) {
    prettyMatrix.data.add(
      groupInfo.deviceSpecClustersOrder[i].substring(startIndx)
    );
    prettyMatrix.data.addAll(matrix[i].map(f));
  }
  print(title);
  print(prettyMatrix);
}

Map<CoverageMatrix, Map<DeviceSpec, Device>> buildCoverage2MatchMapping(
  List<Map<DeviceSpec, Device>> allMatches,
  GroupInfo groupInfo
) {
  Map<CoverageMatrix, Map<DeviceSpec, Device>> cov2match
    = <CoverageMatrix, Map<DeviceSpec, Device>>{};
  for (Map<DeviceSpec, Device> match in allMatches) {
    CoverageMatrix cov = new CoverageMatrix(groupInfo);
    cov.fill(match, isNotCovered);
    cov2match[cov] = match;
  }
  return cov2match;
}

/// Find a small number of mappings which cover the maximum app-device coverage
/// feasible in given the available devices and specs.  The problem can be
/// treated as a set cover problem which is NP-complete and the implementation
/// follow the spirit of greedy algorithm which is O(log(n)).
/// [ref link]: https://en.wikipedia.org/wiki/Set_cover_problem
Set<Map<DeviceSpec, Device>> findMinimumMappings(
  Map<CoverageMatrix, Map<DeviceSpec, Device>> cov2match,
  CoverageMatrix base
) {
  Set<CoverageMatrix> minSet = new Set<CoverageMatrix>();
  while (true) {
    CoverageMatrix currentBestCoverage = null;
    int maxReward = 0;
    for (CoverageMatrix coverage in cov2match.keys) {
      if (minSet.contains(coverage)) continue;
      int reward = computeReward(base, coverage);
      if (maxReward < reward) {
        maxReward = reward;
        currentBestCoverage = coverage;
      }
    }
    if (currentBestCoverage == null) break;
    minSet.add(currentBestCoverage);
    base.union(currentBestCoverage);
  }
  CoverageMatrix.printCoverageMatrix(
    'Best app-device coverage matrix:',
    base
  );
  Set<Map<DeviceSpec, Device>> bestMatches = new Set<Map<DeviceSpec, Device>>();
  for (CoverageMatrix coverage in minSet) {
    bestMatches.add(cov2match[coverage]);
  }
  return bestMatches;
}

int computeReward(CoverageMatrix base, CoverageMatrix newCoverage) {
  int reward = 0;
  for (int i = 0; i < base.matrix.length; i++) {
    List<int> row = base.matrix[i];
    for (int j = 0; j < row.length; j++) {
      if (base.matrix[i][j] == cannotBeCovered
          &&
          newCoverage.matrix[i][j] == isNotCovered)
        reward++;
    }
  }
  return reward;
}
