"""Development sign-in for the local stack (docs/LOCAL_SETUP.md).

``AUTH_PROVIDERS`` decides what the login page offers, ``seed_dev_admin``
creates the local admin from ``DEV_ADMIN_EMAIL``/``DEV_ADMIN_PASSWORD``, and
``check_dev_auth_allowed`` keeps both out of anything but ``MODE=dev``.
"""

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from flask import Flask
from werkzeug.security import check_password_hash

import miminet_auth
from miminet_auth import DEV_ADMIN_ROLE, check_dev_auth_allowed, seed_dev_admin


# --- prod guard ---------------------------------------------------------------


@pytest.mark.parametrize("mode", ["prod", "staging"])
def test_password_provider_is_refused_outside_dev(monkeypatch, mode):
    monkeypatch.setattr(miminet_auth, "AUTH_PROVIDERS", ["password", "vk"])
    monkeypatch.delenv("DEV_ADMIN_PASSWORD", raising=False)

    with pytest.raises(RuntimeError, match="AUTH_PROVIDERS=password"):
        check_dev_auth_allowed(mode)


def test_dev_admin_password_is_refused_outside_dev(monkeypatch):
    monkeypatch.setattr(miminet_auth, "AUTH_PROVIDERS", ["vk", "yandex"])
    monkeypatch.setenv("DEV_ADMIN_PASSWORD", "admin")

    with pytest.raises(RuntimeError, match="DEV_ADMIN_PASSWORD"):
        check_dev_auth_allowed("prod")


def test_prod_defaults_pass_the_guard(monkeypatch):
    monkeypatch.setattr(miminet_auth, "AUTH_PROVIDERS", ["vk", "yandex"])
    monkeypatch.delenv("DEV_ADMIN_PASSWORD", raising=False)

    check_dev_auth_allowed("prod")


def test_dev_allows_everything(monkeypatch):
    monkeypatch.setattr(miminet_auth, "AUTH_PROVIDERS", ["password"])
    monkeypatch.setenv("DEV_ADMIN_PASSWORD", "admin")

    check_dev_auth_allowed("dev")


# --- admin seed ---------------------------------------------------------------


@pytest.fixture
def user_store(monkeypatch):
    """Stub User.query and db.session; ``existing`` is what the lookup finds."""
    store = SimpleNamespace(existing=None, added=[])

    query = MagicMock()
    query.filter_by.side_effect = lambda **kw: MagicMock(
        first=MagicMock(return_value=store.existing)
    )

    def make_user(**kwargs):
        user = SimpleNamespace(role=None, password_hash=None, **kwargs)
        return user

    user_cls = MagicMock(side_effect=make_user)
    user_cls.query = query
    monkeypatch.setattr(miminet_auth, "User", user_cls)

    db = MagicMock()
    db.session.add.side_effect = store.added.append
    monkeypatch.setattr(miminet_auth, "db", db)
    store.db = db
    return store


@pytest.fixture
def admin_env(monkeypatch):
    monkeypatch.setenv("DEV_ADMIN_EMAIL", "admin@local")
    monkeypatch.setenv("DEV_ADMIN_PASSWORD", "admin")


def test_seed_creates_admin(user_store, admin_env):
    seed_dev_admin(Flask(__name__))

    (user,) = user_store.added
    assert user.email == "admin@local"
    assert user.role == DEV_ADMIN_ROLE
    assert check_password_hash(user.password_hash, "admin")
    user_store.db.session.commit.assert_called_once()


def test_seed_updates_existing_user_without_duplicate(user_store, admin_env):
    user_store.existing = SimpleNamespace(
        email="admin@local", role=0, password_hash="stale"
    )

    seed_dev_admin(Flask(__name__))

    assert user_store.added == []
    assert user_store.existing.role == DEV_ADMIN_ROLE
    assert check_password_hash(user_store.existing.password_hash, "admin")


def test_seed_keeps_higher_role(user_store, admin_env):
    user_store.existing = SimpleNamespace(
        email="admin@local", role=5, password_hash="x"
    )

    seed_dev_admin(Flask(__name__))

    assert user_store.existing.role == 5


def test_seed_is_skipped_without_credentials(user_store, monkeypatch):
    monkeypatch.delenv("DEV_ADMIN_EMAIL", raising=False)
    monkeypatch.setenv("DEV_ADMIN_PASSWORD", "admin")

    seed_dev_admin(Flask(__name__))

    assert user_store.added == []
    user_store.db.session.commit.assert_not_called()


# --- login page -----------------------------------------------------------------


@pytest.fixture
def login_page(monkeypatch):
    from app import app as flask_app

    def render(providers):
        monkeypatch.setattr(miminet_auth, "AUTH_PROVIDERS", providers)
        response = flask_app.test_client().get("/auth/login.html")
        assert response.status_code == 200
        return response.get_data(as_text=True)

    return render


def test_login_page_default_shows_only_oauth(login_page):
    html = login_page(["vk", "yandex"])

    assert 'name="password"' not in html
    assert "vk_login" in html and "yandex_login" in html


def test_login_page_password_only(login_page):
    html = login_page(["password"])

    assert 'name="password"' in html
    assert "vk_login" not in html and "yandex_login" not in html


def test_login_page_all_providers(login_page):
    html = login_page(["password", "vk", "yandex"])

    assert 'name="password"' in html
    assert "vk_login" in html and "yandex_login" in html
