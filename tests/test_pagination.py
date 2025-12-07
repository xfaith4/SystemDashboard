"""Tests for pagination module."""

import pytest
import base64
import json
import os
import sys

# Add the app directory to the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

from pagination import (
    KeysetPaginator,
    OffsetPaginator,
    create_keyset_paginator,
    create_offset_paginator
)


class TestKeysetPaginator:
    """Test KeysetPaginator class."""
    
    def test_initialization(self):
        """Test paginator initialization."""
        paginator = KeysetPaginator('timestamp', 'ASC')
        assert paginator.order_column == 'timestamp'
        assert paginator.order_direction == 'ASC'
    
    def test_initialization_invalid_direction(self):
        """Test initialization with invalid direction."""
        with pytest.raises(ValueError, match="must be 'ASC' or 'DESC'"):
            KeysetPaginator('id', 'INVALID')
    
    def test_build_where_clause_no_cursor(self):
        """Test building WHERE clause without cursor."""
        paginator = KeysetPaginator('timestamp', 'ASC')
        where, params = paginator.build_where_clause(None)
        
        assert where == '1=1'
        assert params == []
    
    def test_build_where_clause_asc(self):
        """Test building WHERE clause for ascending order."""
        paginator = KeysetPaginator('timestamp', 'ASC')
        
        # Create a cursor
        cursor_value = '2025-12-07 12:00:00'
        cursor = paginator._encode_cursor(cursor_value)
        
        where, params = paginator.build_where_clause(cursor)
        
        assert 'timestamp >' in where
        assert params == [cursor_value]
    
    def test_build_where_clause_desc(self):
        """Test building WHERE clause for descending order."""
        paginator = KeysetPaginator('timestamp', 'DESC')
        
        cursor_value = '2025-12-07 12:00:00'
        cursor = paginator._encode_cursor(cursor_value)
        
        where, params = paginator.build_where_clause(cursor)
        
        assert 'timestamp <' in where
        assert params == [cursor_value]
    
    def test_build_where_clause_invalid_cursor(self):
        """Test building WHERE clause with invalid cursor."""
        paginator = KeysetPaginator('timestamp', 'ASC')
        
        # Invalid base64
        where, params = paginator.build_where_clause('invalid!!!cursor')
        assert where == '1=1'
        assert params == []
    
    def test_build_query_basic(self):
        """Test building complete query."""
        paginator = KeysetPaginator('id', 'ASC')
        
        base_query = "SELECT * FROM devices"
        query, params = paginator.build_query(base_query, cursor=None, limit=50)
        
        assert 'SELECT * FROM devices' in query
        assert 'ORDER BY id ASC' in query
        assert 'LIMIT ?' in query
        assert params == [51]  # limit + 1
    
    def test_build_query_with_cursor(self):
        """Test building query with cursor."""
        paginator = KeysetPaginator('id', 'ASC')
        
        cursor = paginator._encode_cursor(100)
        base_query = "SELECT * FROM devices"
        query, params = paginator.build_query(base_query, cursor=cursor, limit=25)
        
        assert 'id >' in query
        assert 'ORDER BY id ASC' in query
        assert 'LIMIT ?' in query
        assert params == [100, 26]
    
    def test_build_query_with_additional_where(self):
        """Test building query with additional WHERE conditions."""
        paginator = KeysetPaginator('timestamp', 'DESC')
        
        base_query = "SELECT * FROM logs"
        query, params = paginator.build_query(
            base_query,
            cursor=None,
            limit=100,
            additional_where="severity = 'error'"
        )
        
        assert "severity = 'error'" in query
        assert 'ORDER BY timestamp DESC' in query
    
    def test_create_cursor(self):
        """Test cursor creation from row."""
        paginator = KeysetPaginator('id', 'ASC')
        
        row = {'id': 42, 'name': 'test'}
        cursor = paginator.create_cursor(row)
        
        # Decode and verify
        decoded = paginator._decode_cursor(cursor)
        assert decoded == 42
    
    def test_create_cursor_missing_column(self):
        """Test cursor creation with missing order column."""
        paginator = KeysetPaginator('id', 'ASC')
        
        row = {'name': 'test'}  # Missing 'id'
        
        with pytest.raises(ValueError, match="missing order column"):
            paginator.create_cursor(row)
    
    def test_paginate_results_no_more_pages(self):
        """Test paginating results with no more pages."""
        paginator = KeysetPaginator('id', 'ASC')
        
        rows = [
            {'id': 1, 'name': 'a'},
            {'id': 2, 'name': 'b'},
            {'id': 3, 'name': 'c'}
        ]
        
        result = paginator.paginate_results(rows, limit=5)
        
        assert result['count'] == 3
        assert result['has_more'] is False
        assert result['next_cursor'] is None
        assert len(result['data']) == 3
    
    def test_paginate_results_has_more_pages(self):
        """Test paginating results with more pages."""
        paginator = KeysetPaginator('id', 'ASC')
        
        rows = [
            {'id': 1, 'name': 'a'},
            {'id': 2, 'name': 'b'},
            {'id': 3, 'name': 'c'}
        ]
        
        result = paginator.paginate_results(rows, limit=2)
        
        assert result['count'] == 2
        assert result['has_more'] is True
        assert result['next_cursor'] is not None
        assert len(result['data']) == 2
        
        # Verify cursor points to last item in returned data
        last_id = result['data'][-1]['id']
        decoded_cursor = paginator._decode_cursor(result['next_cursor'])
        assert decoded_cursor == last_id
    
    def test_encode_decode_cursor(self):
        """Test cursor encoding and decoding."""
        paginator = KeysetPaginator('timestamp', 'ASC')
        
        test_values = [
            '2025-12-07 12:00:00',
            1234567890,
            'test-value'
        ]
        
        for value in test_values:
            encoded = paginator._encode_cursor(value)
            decoded = paginator._decode_cursor(encoded)
            assert decoded == value
    
    def test_cursor_is_base64(self):
        """Test that cursor is valid base64."""
        paginator = KeysetPaginator('id', 'ASC')
        
        cursor = paginator._encode_cursor(42)
        
        # Should be valid base64
        try:
            decoded_bytes = base64.b64decode(cursor.encode())
            json.loads(decoded_bytes.decode())
        except Exception as e:
            pytest.fail(f"Cursor is not valid base64 JSON: {e}")


class TestOffsetPaginator:
    """Test OffsetPaginator class."""
    
    def test_calculate_offset_first_page(self):
        """Test offset calculation for first page."""
        offset = OffsetPaginator.calculate_offset(page=1, per_page=50)
        assert offset == 0
    
    def test_calculate_offset_second_page(self):
        """Test offset calculation for second page."""
        offset = OffsetPaginator.calculate_offset(page=2, per_page=50)
        assert offset == 50
    
    def test_calculate_offset_large_page(self):
        """Test offset calculation for large page number."""
        offset = OffsetPaginator.calculate_offset(page=10, per_page=25)
        assert offset == 225
    
    def test_calculate_offset_invalid_page(self):
        """Test offset calculation with invalid page number."""
        offset = OffsetPaginator.calculate_offset(page=0, per_page=50)
        assert offset == 0
        
        offset = OffsetPaginator.calculate_offset(page=-5, per_page=50)
        assert offset == 0
    
    def test_build_query_basic(self):
        """Test building basic query."""
        base_query = "SELECT * FROM devices"
        query, params = OffsetPaginator.build_query(base_query, page=1, per_page=50)
        
        assert 'SELECT * FROM devices' in query
        assert 'LIMIT ?' in query
        assert 'OFFSET ?' in query
        assert params == [50, 0]
    
    def test_build_query_with_order(self):
        """Test building query with ORDER BY."""
        base_query = "SELECT * FROM devices"
        query, params = OffsetPaginator.build_query(
            base_query,
            page=2,
            per_page=25,
            order_by="timestamp DESC"
        )
        
        assert 'ORDER BY timestamp DESC' in query
        assert params == [25, 25]
    
    def test_calculate_total_pages_zero_items(self):
        """Test calculating pages with zero items."""
        total = OffsetPaginator.calculate_total_pages(total_items=0, per_page=50)
        assert total == 0
    
    def test_calculate_total_pages_exact_multiple(self):
        """Test calculating pages when items are exact multiple."""
        total = OffsetPaginator.calculate_total_pages(total_items=100, per_page=50)
        assert total == 2
    
    def test_calculate_total_pages_with_remainder(self):
        """Test calculating pages with remainder."""
        total = OffsetPaginator.calculate_total_pages(total_items=103, per_page=50)
        assert total == 3
    
    def test_calculate_total_pages_less_than_page_size(self):
        """Test calculating pages with fewer items than page size."""
        total = OffsetPaginator.calculate_total_pages(total_items=25, per_page=50)
        assert total == 1
    
    def test_create_page_metadata_first_page(self):
        """Test page metadata for first page."""
        metadata = OffsetPaginator.create_page_metadata(
            page=1,
            per_page=50,
            total_items=200
        )
        
        assert metadata['page'] == 1
        assert metadata['per_page'] == 50
        assert metadata['total_items'] == 200
        assert metadata['total_pages'] == 4
        assert metadata['has_prev'] is False
        assert metadata['has_next'] is True
    
    def test_create_page_metadata_middle_page(self):
        """Test page metadata for middle page."""
        metadata = OffsetPaginator.create_page_metadata(
            page=2,
            per_page=50,
            total_items=200
        )
        
        assert metadata['page'] == 2
        assert metadata['has_prev'] is True
        assert metadata['has_next'] is True
    
    def test_create_page_metadata_last_page(self):
        """Test page metadata for last page."""
        metadata = OffsetPaginator.create_page_metadata(
            page=4,
            per_page=50,
            total_items=200
        )
        
        assert metadata['page'] == 4
        assert metadata['has_prev'] is True
        assert metadata['has_next'] is False
    
    def test_create_page_metadata_only_page(self):
        """Test page metadata when only one page exists."""
        metadata = OffsetPaginator.create_page_metadata(
            page=1,
            per_page=50,
            total_items=25
        )
        
        assert metadata['total_pages'] == 1
        assert metadata['has_prev'] is False
        assert metadata['has_next'] is False


class TestFactoryFunctions:
    """Test factory functions."""
    
    def test_create_keyset_paginator(self):
        """Test keyset paginator factory."""
        paginator = create_keyset_paginator('timestamp', 'DESC')
        
        assert isinstance(paginator, KeysetPaginator)
        assert paginator.order_column == 'timestamp'
        assert paginator.order_direction == 'DESC'
    
    def test_create_offset_paginator(self):
        """Test offset paginator factory."""
        paginator = create_offset_paginator()
        
        # Returns the class itself since it's stateless
        assert paginator == OffsetPaginator


class TestPaginationScenarios:
    """Test realistic pagination scenarios."""
    
    def test_keyset_pagination_workflow(self):
        """Test complete keyset pagination workflow."""
        paginator = KeysetPaginator('id', 'ASC')
        
        # Simulate database results (page 1)
        page1_results = [
            {'id': 1, 'name': 'Item 1'},
            {'id': 2, 'name': 'Item 2'},
            {'id': 3, 'name': 'Item 3'}
        ]
        
        page1 = paginator.paginate_results(page1_results, limit=2)
        
        assert page1['count'] == 2
        assert page1['has_more'] is True
        
        # Use cursor to fetch page 2
        cursor = page1['next_cursor']
        where, params = paginator.build_where_clause(cursor)
        
        assert 'id >' in where
        assert params[0] == 2  # Last ID from page 1
    
    def test_offset_pagination_workflow(self):
        """Test complete offset pagination workflow."""
        # Simulate 250 total items, 50 per page
        total_items = 250
        per_page = 50
        
        # Page 1
        query1, params1 = OffsetPaginator.build_query(
            "SELECT * FROM items",
            page=1,
            per_page=per_page
        )
        assert params1 == [50, 0]
        
        metadata1 = OffsetPaginator.create_page_metadata(1, per_page, total_items)
        assert metadata1['total_pages'] == 5
        assert metadata1['has_next'] is True
        
        # Page 3
        query3, params3 = OffsetPaginator.build_query(
            "SELECT * FROM items",
            page=3,
            per_page=per_page
        )
        assert params3 == [50, 100]
        
        # Last page
        query5, params5 = OffsetPaginator.build_query(
            "SELECT * FROM items",
            page=5,
            per_page=per_page
        )
        metadata5 = OffsetPaginator.create_page_metadata(5, per_page, total_items)
        assert metadata5['has_next'] is False
