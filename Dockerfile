FROM quay.io/jupyter/pytorch-notebook:cuda12-latest

USER root
RUN curl -fsSL https://code-server.dev/install.sh | sh
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

USER ${NB_UID}
WORKDIR /home/jovyan


ENTRYPOINT []
CMD ["/usr/bin/code-server"]