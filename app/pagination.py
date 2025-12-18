"""
Pagination utilities for efficient data retrieval.

This module provides:
- Keyset pagination (cursor-based) for better performance with large datasets
- Offset pagination (traditional) for backward compatibility
- Page metadata calculation
"""

from typing import Optional, Dict, Any, List, Tuple
import base64
import json


class KeysetPaginator:
    """
    Keyset (cursor-based) pagination for efficient large dataset navigation.
    
    More efficient than OFFSET pagination because it doesn't require counting
    all previous rows and uses indexed columns for positioning.
    """
    
    def __init__(self, order_column: str, order_direction: str = 'ASC'):
        """
        Initialize keyset paginator.
        
        Args:
            order_column: Column name to order by (must be indexed)
            order_direction: 'ASC' or 'DESC'
        """
        self.order_column = order_column
        self.order_direction = order_direction.upper()
        
        if self.order_direction not in ('ASC', 'DESC'):
            raise ValueError("order_direction must be 'ASC' or 'DESC'")
    
    def build_where_clause(self, cursor: Optional[str] = None) -> Tuple[str, List[Any]]:
        """
        Build WHERE clause for keyset pagination.
        
        Args:
            cursor: Base64-encoded cursor value from previous page
            
        Returns:
            Tuple of (where_clause, params)
            
        Example:
            where, params = paginator.build_where_clause(cursor)
            query = f"SELECT * FROM table WHERE {where} ORDER BY timestamp {direction} LIMIT ?"
            cursor.execute(query, params + [limit])
        """
        if not cursor:
            return ('1=1', [])
        
        try:
            cursor_value = self._decode_cursor(cursor)
        except (ValueError, json.JSONDecodeError):
            # Invalid cursor, return all results
            return ('1=1', [])
        
        # Build comparison based on direction
        if self.order_direction == 'ASC':
            operator = '>'
        else:
            operator = '<'
        
        where_clause = f"{self.order_column} {operator} ?"
        params = [cursor_value]
        
        return (where_clause, params)
    
    def build_query(
        self,
        base_query: str,
        cursor: Optional[str] = None,
        limit: int = 50,
        additional_where: Optional[str] = None
    ) -> Tuple[str, List[Any]]:
        """
        Build complete paginated query.
        
        Args:
            base_query: Base SELECT query (without WHERE, ORDER BY, or LIMIT)
            cursor: Cursor from previous page
            limit: Number of records to return
            additional_where: Additional WHERE conditions (will be AND-ed)
            
        Returns:
            Tuple of (complete_query, params)
            
        Example:
            query, params = paginator.build_query(
                "SELECT * FROM devices",
                cursor="eyJ0aW1lc3RhbXAiOiAiMjAyNS0xMi0wNyJ9",
                limit=50,
                additional_where="status = 'online'"
            )
        """
        keyset_where, keyset_params = self.build_where_clause(cursor)
        
        # Combine WHERE clauses
        where_clauses = [keyset_where]
        if additional_where:
            where_clauses.append(additional_where)
        
        combined_where = ' AND '.join(f"({clause})" for clause in where_clauses)
        
        # Build complete query
        query = f"{base_query} WHERE {combined_where} ORDER BY {self.order_column} {self.order_direction} LIMIT ?"
        params = keyset_params + [limit + 1]  # Fetch one extra to determine if there's a next page
        
        return (query, params)
    
    def create_cursor(self, row: Dict[str, Any]) -> str:
        """
        Create cursor from the last row of results.
        
        Args:
            row: Dictionary representing a database row
            
        Returns:
            Base64-encoded cursor string
            
        Example:
            cursor = paginator.create_cursor({'timestamp': '2025-12-07 12:00:00'})
        """
        cursor_value = row.get(self.order_column)
        if cursor_value is None:
            raise ValueError(f"Row missing order column '{self.order_column}'")
        
        return self._encode_cursor(cursor_value)
    
    def paginate_results(
        self,
        rows: List[Dict[str, Any]],
        limit: int
    ) -> Dict[str, Any]:
        """
        Process query results and generate pagination metadata.
        
        Args:
            rows: List of result rows (should be limit + 1)
            limit: Requested page size
            
        Returns:
            Dict with 'data', 'has_more', and 'next_cursor'
            
        Example:
            results = cursor.fetchall()
            page_data = paginator.paginate_results(results, limit=50)
        """
        has_more = len(rows) > limit
        
        if has_more:
            data = rows[:limit]
            next_cursor = self.create_cursor(data[-1])
        else:
            data = rows
            next_cursor = None
        
        return {
            'data': data,
            'has_more': has_more,
            'next_cursor': next_cursor,
            'count': len(data)
        }
    
    def _encode_cursor(self, value: Any) -> str:
        """Encode cursor value to base64 string."""
        cursor_dict = {self.order_column: value}
        json_str = json.dumps(cursor_dict, default=str)
        return base64.b64encode(json_str.encode()).decode()
    
    def _decode_cursor(self, cursor: str) -> Any:
        """Decode cursor from base64 string."""
        json_str = base64.b64decode(cursor.encode()).decode()
        cursor_dict = json.loads(json_str)
        return cursor_dict[self.order_column]


class OffsetPaginator:
    """
    Traditional offset-based pagination.
    
    Simpler than keyset pagination but less efficient for large offsets.
    Use for small datasets or when keyset pagination isn't suitable.
    """
    
    @staticmethod
    def calculate_offset(page: int, per_page: int) -> int:
        """
        Calculate offset for a given page number.
        
        Args:
            page: Page number (1-indexed)
            per_page: Items per page
            
        Returns:
            Offset value for SQL LIMIT clause
        """
        if page < 1:
            page = 1
        return (page - 1) * per_page
    
    @staticmethod
    def build_query(
        base_query: str,
        page: int = 1,
        per_page: int = 50,
        order_by: Optional[str] = None
    ) -> Tuple[str, List[Any]]:
        """
        Build paginated query with OFFSET.
        
        Args:
            base_query: Base SELECT query
            page: Page number (1-indexed)
            per_page: Items per page
            order_by: ORDER BY clause (e.g., "timestamp DESC")
            
        Returns:
            Tuple of (query, params)
        """
        offset = OffsetPaginator.calculate_offset(page, per_page)
        
        query = base_query
        if order_by:
            query += f" ORDER BY {order_by}"
        query += " LIMIT ? OFFSET ?"
        
        return (query, [per_page, offset])
    
    @staticmethod
    def calculate_total_pages(total_items: int, per_page: int) -> int:
        """
        Calculate total number of pages.
        
        Args:
            total_items: Total number of items
            per_page: Items per page
            
        Returns:
            Total number of pages
        """
        if total_items == 0:
            return 0
        return (total_items + per_page - 1) // per_page
    
    @staticmethod
    def create_page_metadata(
        page: int,
        per_page: int,
        total_items: int
    ) -> Dict[str, Any]:
        """
        Create pagination metadata.
        
        Args:
            page: Current page number
            per_page: Items per page
            total_items: Total number of items
            
        Returns:
            Dict with pagination metadata
        """
        total_pages = OffsetPaginator.calculate_total_pages(total_items, per_page)
        
        return {
            'page': page,
            'per_page': per_page,
            'total_items': total_items,
            'total_pages': total_pages,
            'has_prev': page > 1,
            'has_next': page < total_pages
        }


def create_keyset_paginator(
    order_column: str,
    order_direction: str = 'ASC'
) -> KeysetPaginator:
    """
    Factory function to create a keyset paginator.
    
    Args:
        order_column: Column to order by
        order_direction: 'ASC' or 'DESC'
        
    Returns:
        KeysetPaginator instance
    """
    return KeysetPaginator(order_column, order_direction)


def create_offset_paginator() -> OffsetPaginator:
    """
    Factory function to create an offset paginator.
    
    Returns:
        OffsetPaginator instance (stateless, so just return class)
    """
    return OffsetPaginator
