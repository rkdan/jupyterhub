FROM quay.io/jupyter/pytorch-notebook:cuda12-latest

USER root
RUN curl -fsSL https://code-server.dev/install.sh | sh
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

RUN mkdir -p /opt/code-extensions \
    && code-server --extensions-dir /opt/code-extensions --install-extension ms-python.python \
    && code-server --extensions-dir /opt/code-extensions --install-extension ms-toolsai.jupyter \
    && chown -R ${NB_UID}:${NB_GID} /opt/code-extensions

USER ${NB_UID}
WORKDIR /home/jovyan


ENTRYPOINT []
CMD ["/usr/bin/code-server"]