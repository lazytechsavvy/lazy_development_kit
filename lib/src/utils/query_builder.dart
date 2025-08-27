/// Query builder for constructing Strapi API queries.
class LDKQueryBuilder {
  /// Creates a new [LDKQueryBuilder] instance.
  LDKQueryBuilder();

  final Map<String, dynamic> _filters = {};
  final List<String> _sorts = [];
  final List<String> _populate = [];
  int? _limit;
  int? _start;
  int? _page;
  int? _pageSize;

  /// Adds a filter condition.
  LDKQueryBuilder where(
    String field, {
    dynamic equals,
    dynamic notEquals,
    dynamic contains,
    dynamic notContains,
    dynamic containsi,
    dynamic notContainsi,
    dynamic startsWith,
    dynamic endsWith,
    dynamic greaterThan,
    dynamic greaterThanOrEqual,
    dynamic lessThan,
    dynamic lessThanOrEqual,
    List<dynamic>? isIn,
    List<dynamic>? notIn,
    bool? isNull,
    bool? isNotNull,
  }) {
    final conditions = <String, dynamic>{};

    if (equals != null) conditions['\$eq'] = equals;
    if (notEquals != null) conditions['\$ne'] = notEquals;
    if (contains != null) conditions['\$contains'] = contains;
    if (notContains != null) conditions['\$notContains'] = notContains;
    if (containsi != null) conditions['\$containsi'] = containsi;
    if (notContainsi != null) conditions['\$notContainsi'] = notContainsi;
    if (startsWith != null) conditions['\$startsWith'] = startsWith;
    if (endsWith != null) conditions['\$endsWith'] = endsWith;
    if (greaterThan != null) conditions['\$gt'] = greaterThan;
    if (greaterThanOrEqual != null) conditions['\$gte'] = greaterThanOrEqual;
    if (lessThan != null) conditions['\$lt'] = lessThan;
    if (lessThanOrEqual != null) conditions['\$lte'] = lessThanOrEqual;
    if (isIn != null) conditions['\$in'] = isIn;
    if (notIn != null) conditions['\$notIn'] = notIn;
    if (isNull == true) conditions['\$null'] = true;
    if (isNotNull == true) conditions['\$notNull'] = true;

    if (conditions.isNotEmpty) {
      _filters[field] = conditions;
    }

    return this;
  }

  /// Adds an AND condition.
  LDKQueryBuilder and(List<LDKQueryBuilder> conditions) {
    final andConditions = conditions.map((c) => c._filters).toList();
    if (andConditions.isNotEmpty) {
      _filters['\$and'] = andConditions;
    }
    return this;
  }

  /// Adds an OR condition.
  LDKQueryBuilder or(List<LDKQueryBuilder> conditions) {
    final orConditions = conditions.map((c) => c._filters).toList();
    if (orConditions.isNotEmpty) {
      _filters['\$or'] = orConditions;
    }
    return this;
  }

  /// Adds sorting by field.
  LDKQueryBuilder sort(String field, {bool descending = false}) {
    final sortOrder = descending ? 'desc' : 'asc';
    _sorts.add('$field:$sortOrder');
    return this;
  }

  /// Adds multiple sort conditions.
  LDKQueryBuilder sortBy(Map<String, bool> sorts) {
    for (final entry in sorts.entries) {
      sort(entry.key, descending: entry.value);
    }
    return this;
  }

  /// Adds population of related fields.
  LDKQueryBuilder populate(String field) {
    _populate.add(field);
    return this;
  }

  /// Adds multiple population fields.
  LDKQueryBuilder populateAll(List<String> fields) {
    _populate.addAll(fields);
    return this;
  }

  /// Sets the maximum number of results to return.
  LDKQueryBuilder limit(int count) {
    _limit = count;
    return this;
  }

  /// Sets the number of results to skip.
  LDKQueryBuilder start(int count) {
    _start = count;
    return this;
  }

  /// Sets pagination parameters.
  LDKQueryBuilder paginate({required int page, required int pageSize}) {
    _page = page;
    _pageSize = pageSize;
    return this;
  }

  /// Builds the query parameters for the API request.
  Map<String, dynamic> build() {
    final params = <String, dynamic>{};

    // Add filters
    if (_filters.isNotEmpty) {
      params['filters'] = _filters;
    }

    // Add sorting
    if (_sorts.isNotEmpty) {
      params['sort'] = _sorts;
    }

    // Add population
    if (_populate.isNotEmpty) {
      params['populate'] = _populate;
    }

    // Add pagination
    if (_page != null && _pageSize != null) {
      params['pagination'] = {
        'page': _page,
        'pageSize': _pageSize,
      };
    } else {
      if (_limit != null) {
        params['pagination'] = {'limit': _limit};
      }
      if (_start != null) {
        params['pagination'] = {
          ...?params['pagination'] as Map<String, dynamic>?,
          'start': _start,
        };
      }
    }

    return params;
  }

  /// Converts the query to URL query parameters.
  Map<String, String> toQueryParameters() {
    final built = build();
    final queryParams = <String, String>{};

    for (final entry in built.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value is Map<String, dynamic>) {
        _flattenMap(value, key, queryParams);
      } else if (value is List) {
        for (int i = 0; i < value.length; i++) {
          final item = value[i];
          if (item is Map<String, dynamic>) {
            _flattenMap(item, '$key[$i]', queryParams);
          } else {
            queryParams['$key[$i]'] = item.toString();
          }
        }
      } else {
        queryParams[key] = value.toString();
      }
    }

    return queryParams;
  }

  /// Flattens a nested map into query parameters.
  void _flattenMap(
    Map<String, dynamic> map,
    String prefix,
    Map<String, String> result,
  ) {
    for (final entry in map.entries) {
      final key = '${prefix}[${entry.key}]';
      final value = entry.value;

      if (value is Map<String, dynamic>) {
        _flattenMap(value, key, result);
      } else if (value is List) {
        for (int i = 0; i < value.length; i++) {
          final item = value[i];
          if (item is Map<String, dynamic>) {
            _flattenMap(item, '$key[$i]', result);
          } else {
            result['$key[$i]'] = item.toString();
          }
        }
      } else {
        result[key] = value.toString();
      }
    }
  }

  /// Creates a copy of this query builder.
  LDKQueryBuilder copy() {
    final copy = LDKQueryBuilder();
    copy._filters.addAll(_filters);
    copy._sorts.addAll(_sorts);
    copy._populate.addAll(_populate);
    copy._limit = _limit;
    copy._start = _start;
    copy._page = _page;
    copy._pageSize = _pageSize;
    return copy;
  }

  /// Clears all query conditions.
  LDKQueryBuilder clear() {
    _filters.clear();
    _sorts.clear();
    _populate.clear();
    _limit = null;
    _start = null;
    _page = null;
    _pageSize = null;
    return this;
  }

  @override
  String toString() {
    return 'LDKQueryBuilder(${build()})';
  }
}
