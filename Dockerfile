FROM kicad/kicad:10.0.5

ENV DEBIAN_FRONTEND=noninteractive

# Create a non-root user
ARG ORIGINALUSER=kicad
ARG USERNAME=user
ARG UID=1000
ARG GID=1000

USER root

# Install Python, pip, and venv
RUN apt-get update && apt-get install -y \
	python3 \
	python3-pip \
	python3-venv \
	make \
	xvfb \
	poppler-utils \
	fonts-freefont-ttf \
	zip \
	python3-numpy \
	python3-scipy \
	python3-shapely \
	python3-pil \
	&& rm -rf /var/lib/apt/lists/*

# uv, for project environments built on the system Python (e.g. the flex
# board generator's setup.sh)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Create a Python virtual environment
RUN python3 -m venv /opt/venv

# Activate the virtual environment and install Python packages
RUN /opt/venv/bin/pip install --upgrade pip \
	&& /opt/venv/bin/pip install git+https://github.com/snhobbs/kicad-xyrs.git@master \
	&& /opt/venv/bin/pip install git+https://github.com/snhobbs/kicad-testpoints.git@master \
	&& /opt/venv/bin/pip install git+https://github.com/snhobbs/InteractiveHtmlBom.git@master \
	&& /opt/venv/bin/pip install sexpdata pyyaml


RUN groupmod --gid ${GID} kicad \
	&& usermod --uid ${UID} --gid ${GID} kicad \
	&& usermod --login ${USERNAME} \
	--home /home/${USERNAME} \
	--move-home kicad \
	&& echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
	&& chmod 0440 /etc/sudoers.d/${USERNAME}

# KiCad Routing Tools (autorouter): action plugin + CLI in py_router/.
# build_router.py fetches the prebuilt Rust core (grid_router.so) for the tag.
# Linked into the system plugin dir so a mounted $HOME can't hide it.
ARG KICAD_ROUTING_TOOLS_TAG=v0.22.1
ENV KICAD_ROUTING_TOOLS=/opt/KiCadRoutingTools
RUN git clone --depth 1 --branch ${KICAD_ROUTING_TOOLS_TAG} \
	https://github.com/drandyhaas/KiCadRoutingTools.git ${KICAD_ROUTING_TOOLS} \
	&& cd ${KICAD_ROUTING_TOOLS} \
	&& python3 build_router.py --tag ${KICAD_ROUTING_TOOLS_TAG} \
	&& rm -rf .git tests docs kicad_files \
	&& python3 -c "import sys; sys.path.insert(0, 'rust_router'); import grid_router; print('grid_router', grid_router.__version__)" \
	&& mkdir -p /usr/share/kicad/scripting/plugins \
	&& ln -s ${KICAD_ROUTING_TOOLS} /usr/share/kicad/scripting/plugins/KiCadRoutingTools



# Set environment variables to use the virtual environment
ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONPATH="/usr/lib/python3/dist-packages"

# Set environment variables for the new user
ENV HOME=/home/${USERNAME}
WORKDIR /home/${USERNAME}
USER ${USERNAME}

CMD ["bash"]
