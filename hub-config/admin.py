import os
from jupyterhub.auth import DummyAuthenticator
from traitlets import Unicode

class TwoPasswordAuth(DummyAuthenticator):
    admin_password = Unicode("", config=True)

    async def authenticate(self, handler, data):
        username = data["username"]
        password = data["password"]
        if username in self.admin_users:
            if password == self.admin_password:
                return username
            return None
        if password == self.password:
            return username
        return None

c.JupyterHub.authenticator_class = TwoPasswordAuth
c.TwoPasswordAuth.password = os.environ["JHUB_USER_PASSWORD"]
c.TwoPasswordAuth.admin_password = os.environ["JHUB_ADMIN_PASSWORD"]
c.TwoPasswordAuth.admin_users = {"admin"}