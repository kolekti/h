# -*- coding: utf-8 -*-

from __future__ import unicode_literals

import pytest

from h.views import api_profile


class TestProfile(object):
    def test_profile_view_proxies_to_session(self, session_profile, pyramid_request):
        session_profile.return_value = {'foo': 'bar'}
        result = api_profile.profile(pyramid_request)
        assert result == {'foo': 'bar'}

    @pytest.fixture
    def session_profile(self, patch):
        return patch('h.session.profile')
