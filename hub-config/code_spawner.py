from kubespawner.spawner import KubeSpawner
from jupyterhub.spawner import _quote_safe

class VSCodeKubeSpawner(KubeSpawner):
    def get_args(self):
        args = ["--auth", "none"]
        args += ["--disable-telemetry"]

        ip = "0.0.0.0"
        if self.ip:
            ip = _quote_safe(self.ip)

        port = 8888
        if self.port:
            port = self.port
        elif self.server and self.server.port:
            port = self.server.port

        args += ["--bind-addr", f"{ip}:{port}"]

        if self.notebook_dir:
            notebook_dir = self.format_string(self.notebook_dir)
            args += ["--user-data-dir", _quote_safe(notebook_dir)]

        if self.debug:
            args += ["-vvv"]

        args.extend(self.args)
        return args

c.JupyterHub.spawner_class = VSCodeKubeSpawner
c.VSCodeKubeSpawner.namespace = "jhub"
c.VSCodeKubeSpawner.working_dir = "/home/jovyan"
c.VSCodeKubeSpawner.cmd = ["code-server"]