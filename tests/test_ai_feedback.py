"""
Test suite for AI Feedback API endpoints.
Tests persistence, retrieval, and review status workflow for AI-generated event explanations.
"""
import os
import sys
import pytest
import json
from unittest.mock import patch, MagicMock

# Add the app directory to the path so we can import app
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

import app as flask_app


@pytest.fixture
def client():
    """Create a test client for the Flask app."""
    flask_app.app.config['TESTING'] = True
    with flask_app.app.test_client() as client:
        yield client


class TestAIFeedbackEndpoints:
    """Test AI Feedback API endpoints for persistence and review workflow."""
    
    def test_create_feedback_missing_event_message(self, client):
        """Test creating feedback without event_message returns 400."""
        response = client.post('/api/ai/feedback', 
                             json={
                                 'ai_response': 'This is an AI response',
                                 'review_status': 'Viewed'
                             },
                             content_type='application/json')
        assert response.status_code == 400
        data = json.loads(response.data)
        assert 'error' in data
        assert 'event_message' in data['error']
    
    def test_create_feedback_missing_ai_response(self, client):
        """Test creating feedback without ai_response returns 400."""
        response = client.post('/api/ai/feedback',
                             json={
                                 'event_message': 'Test event message',
                                 'review_status': 'Viewed'
                             },
                             content_type='application/json')
        assert response.status_code == 400
        data = json.loads(response.data)
        assert 'error' in data
        assert 'ai_response' in data['error']
    
    def test_create_feedback_invalid_status(self, client):
        """Test creating feedback with invalid status returns 400."""
        response = client.post('/api/ai/feedback',
                             json={
                                 'event_message': 'Test event message',
                                 'ai_response': 'This is an AI response',
                                 'review_status': 'InvalidStatus'
                             },
                             content_type='application/json')
        assert response.status_code == 400
        data = json.loads(response.data)
        assert 'error' in data
        assert 'Invalid review_status' in data['error']
    
    @patch('app.get_db_connection')
    def test_create_feedback_no_database(self, mock_db, client):
        """Test creating feedback when database is unavailable."""
        mock_db.return_value = None
        
        response = client.post('/api/ai/feedback',
                             json={
                                 'event_id': 1001,
                                 'event_source': 'Application Error',
                                 'event_message': 'Test error message',
                                 'event_log_type': 'Application',
                                 'event_level': 'Error',
                                 'ai_response': 'This is an AI response',
                                 'review_status': 'Viewed'
                             },
                             content_type='application/json')
        assert response.status_code == 503
        data = json.loads(response.data)
        assert 'error' in data
    
    @patch('app.get_db_connection')
    def test_create_feedback_success(self, mock_db, client):
        """Test successfully creating feedback entry."""
        # Mock database connection and cursor
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = {
            'id': 1,
            'created_at': '2024-01-01T12:00:00+00:00',
            'updated_at': '2024-01-01T12:00:00+00:00'
        }
        mock_conn.cursor.return_value.__enter__.return_value = mock_cursor
        mock_db.return_value = mock_conn
        
        response = client.post('/api/ai/feedback',
                             json={
                                 'event_id': 1001,
                                 'event_source': 'Application Error',
                                 'event_message': 'Test error message',
                                 'event_log_type': 'Application',
                                 'event_level': 'Error',
                                 'ai_response': 'This is an AI response explaining the error',
                                 'review_status': 'Viewed'
                             },
                             content_type='application/json')
        
        assert response.status_code == 201
        data = json.loads(response.data)
        assert data['status'] == 'ok'
        assert 'id' in data
        assert 'created_at' in data
        assert 'updated_at' in data
    
    @patch('app.get_db_connection')
    def test_list_feedback_no_database(self, mock_db, client):
        """Test listing feedback when database is unavailable."""
        mock_db.return_value = None
        
        response = client.get('/api/ai/feedback')
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['feedback'] == []
        assert data['total'] == 0
        assert data['source'] == 'unavailable'
    
    @patch('app.get_db_connection')
    def test_list_feedback_success(self, mock_db, client):
        """Test successfully listing feedback entries."""
        # Mock database connection and cursor
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = {'count': 2}
        mock_cursor.fetchall.return_value = [
            {
                'id': 1,
                'event_id': 1001,
                'event_source': 'Application Error',
                'event_message': 'Test error 1',
                'event_log_type': 'Application',
                'event_level': 'Error',
                'event_time': '2024-01-01T10:00:00+00:00',
                'ai_response': 'AI explanation 1',
                'review_status': 'Viewed',
                'created_at': '2024-01-01T12:00:00+00:00',
                'updated_at': '2024-01-01T12:00:00+00:00'
            },
            {
                'id': 2,
                'event_id': 2001,
                'event_source': 'System',
                'event_message': 'Test error 2',
                'event_log_type': 'System',
                'event_level': 'Warning',
                'event_time': '2024-01-01T11:00:00+00:00',
                'ai_response': 'AI explanation 2',
                'review_status': 'Pending',
                'created_at': '2024-01-01T13:00:00+00:00',
                'updated_at': '2024-01-01T13:00:00+00:00'
            }
        ]
        mock_conn.cursor.return_value.__enter__.return_value = mock_cursor
        mock_db.return_value = mock_conn
        
        response = client.get('/api/ai/feedback?limit=10')
        assert response.status_code == 200
        data = json.loads(response.data)
        assert len(data['feedback']) == 2
        assert data['total'] == 2
        assert data['source'] == 'database'
        assert data['feedback'][0]['review_status'] == 'Viewed'
        assert data['feedback'][1]['review_status'] == 'Pending'
    
    @patch('app.get_db_connection')
    def test_list_feedback_with_status_filter(self, mock_db, client):
        """Test listing feedback with status filter."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = {'count': 1}
        mock_cursor.fetchall.return_value = [
            {
                'id': 1,
                'event_id': 1001,
                'event_source': 'Application Error',
                'event_message': 'Test error',
                'event_log_type': 'Application',
                'event_level': 'Error',
                'event_time': '2024-01-01T10:00:00+00:00',
                'ai_response': 'AI explanation',
                'review_status': 'Resolved',
                'created_at': '2024-01-01T12:00:00+00:00',
                'updated_at': '2024-01-01T14:00:00+00:00'
            }
        ]
        mock_conn.cursor.return_value.__enter__.return_value = mock_cursor
        mock_db.return_value = mock_conn
        
        response = client.get('/api/ai/feedback?status=Resolved')
        assert response.status_code == 200
        data = json.loads(response.data)
        assert len(data['feedback']) == 1
        assert data['feedback'][0]['review_status'] == 'Resolved'
    
    @patch('app.get_db_connection')
    def test_update_status_no_database(self, mock_db, client):
        """Test updating status when database is unavailable."""
        mock_db.return_value = None
        
        response = client.patch('/api/ai/feedback/1/status',
                              json={'status': 'Resolved'},
                              content_type='application/json')
        assert response.status_code == 503
        data = json.loads(response.data)
        assert 'error' in data
    
    def test_update_status_invalid_status(self, client):
        """Test updating with invalid status returns 400."""
        response = client.patch('/api/ai/feedback/1/status',
                              json={'status': 'InvalidStatus'},
                              content_type='application/json')
        assert response.status_code == 400
        data = json.loads(response.data)
        assert 'error' in data
        assert 'Invalid status' in data['error']
    
    def test_update_status_missing_status(self, client):
        """Test updating without status field returns 400."""
        response = client.patch('/api/ai/feedback/1/status',
                              json={},
                              content_type='application/json')
        assert response.status_code == 400
        data = json.loads(response.data)
        assert 'error' in data
    
    @patch('app.get_db_connection')
    def test_update_status_not_found(self, mock_db, client):
        """Test updating non-existent feedback entry returns 404."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = None
        mock_conn.cursor.return_value.__enter__.return_value = mock_cursor
        mock_db.return_value = mock_conn
        
        response = client.patch('/api/ai/feedback/999/status',
                              json={'status': 'Resolved'},
                              content_type='application/json')
        assert response.status_code == 404
        data = json.loads(response.data)
        assert 'error' in data
    
    @patch('app.get_db_connection')
    def test_update_status_success(self, mock_db, client):
        """Test successfully updating feedback status."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = {
            'id': 1,
            'review_status': 'Resolved',
            'updated_at': '2024-01-01T15:00:00+00:00'
        }
        mock_conn.cursor.return_value.__enter__.return_value = mock_cursor
        mock_db.return_value = mock_conn
        
        response = client.patch('/api/ai/feedback/1/status',
                              json={'status': 'Resolved'},
                              content_type='application/json')
        
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['status'] == 'ok'
        assert data['id'] == 1
        assert data['review_status'] == 'Resolved'
        assert 'updated_at' in data
    
    @patch('app.get_db_connection')
    def test_update_status_workflow_pending_to_viewed(self, mock_db, client):
        """Test status workflow: Pending -> Viewed."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = {
            'id': 1,
            'review_status': 'Viewed',
            'updated_at': '2024-01-01T15:00:00+00:00'
        }
        mock_conn.cursor.return_value.__enter__.return_value = mock_cursor
        mock_db.return_value = mock_conn
        
        response = client.patch('/api/ai/feedback/1/status',
                              json={'status': 'Viewed'},
                              content_type='application/json')
        
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['review_status'] == 'Viewed'
    
    @patch('app.get_db_connection')
    def test_update_status_workflow_viewed_to_resolved(self, mock_db, client):
        """Test status workflow: Viewed -> Resolved."""
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = {
            'id': 1,
            'review_status': 'Resolved',
            'updated_at': '2024-01-01T15:00:00+00:00'
        }
        mock_conn.cursor.return_value.__enter__.return_value = mock_cursor
        mock_db.return_value = mock_conn
        
        response = client.patch('/api/ai/feedback/1/status',
                              json={'status': 'Resolved'},
                              content_type='application/json')
        
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['review_status'] == 'Resolved'


class TestAIFeedbackIntegration:
    """Integration tests for AI feedback workflow."""
    
    @patch('app.get_db_connection')
    def test_complete_feedback_workflow(self, mock_db, client):
        """Test complete workflow: create feedback, list it, update status."""
        mock_conn = MagicMock()
        
        # Mock create feedback
        mock_cursor_create = MagicMock()
        mock_cursor_create.fetchone.return_value = {
            'id': 1,
            'created_at': '2024-01-01T12:00:00+00:00',
            'updated_at': '2024-01-01T12:00:00+00:00'
        }
        
        # Mock list feedback
        mock_cursor_list = MagicMock()
        mock_cursor_list.fetchone.return_value = {'count': 1}
        mock_cursor_list.fetchall.return_value = [
            {
                'id': 1,
                'event_id': 1001,
                'event_source': 'Application Error',
                'event_message': 'Test error',
                'event_log_type': 'Application',
                'event_level': 'Error',
                'event_time': '2024-01-01T10:00:00+00:00',
                'ai_response': 'AI explanation',
                'review_status': 'Viewed',
                'created_at': '2024-01-01T12:00:00+00:00',
                'updated_at': '2024-01-01T12:00:00+00:00'
            }
        ]
        
        # Mock update status
        mock_cursor_update = MagicMock()
        mock_cursor_update.fetchone.return_value = {
            'id': 1,
            'review_status': 'Resolved',
            'updated_at': '2024-01-01T15:00:00+00:00'
        }
        
        # Setup mock to return different cursors for each call
        cursors = [mock_cursor_create, mock_cursor_list, mock_cursor_update]
        mock_conn.cursor.return_value.__enter__.side_effect = cursors
        mock_db.return_value = mock_conn
        
        # Step 1: Create feedback
        create_response = client.post('/api/ai/feedback',
                                    json={
                                        'event_id': 1001,
                                        'event_source': 'Application Error',
                                        'event_message': 'Test error',
                                        'event_log_type': 'Application',
                                        'event_level': 'Error',
                                        'ai_response': 'AI explanation',
                                        'review_status': 'Viewed'
                                    },
                                    content_type='application/json')
        assert create_response.status_code == 201
        
        # Step 2: List feedback
        list_response = client.get('/api/ai/feedback')
        assert list_response.status_code == 200
        list_data = json.loads(list_response.data)
        assert len(list_data['feedback']) == 1
        assert list_data['feedback'][0]['review_status'] == 'Viewed'
        
        # Step 3: Update status to Resolved
        update_response = client.patch('/api/ai/feedback/1/status',
                                      json={'status': 'Resolved'},
                                      content_type='application/json')
        assert update_response.status_code == 200
        update_data = json.loads(update_response.data)
        assert update_data['review_status'] == 'Resolved'
