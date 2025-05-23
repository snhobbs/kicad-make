# Base image
FROM kicad/kicad:9.0
ENV DEBIAN_FRONTEND=noninteractive
# Install required packages
RUN sudo apt-get update
RUN sudo apt-get install -y \
    git \
    libx11-dev \
    x11-apps \
    make \
    python3.11 \
    python3-pip \
    python3-dev \
    python3-venv

RUN sudo apt-get install -y xvfb

# install pdfunite
RUN sudo apt-get install -y poppler-utils

# Set user and group
ARG user=kicad
ARG INSTALL_DIR=/usr/share
# Set the working directory
WORKDIR ${INSTALL_DIR}

# Clone kicad-make and check out desired version
RUN sudo chown ${user} ${INSTALL_DIR}

# Create and activate venv
RUN cd ${INSTALL_DIR} && python3.11 -m venv venv --system-site-packages

# Add venv to path
ENV PATH="${INSTALL_DIR}/venv/bin/:$PATH"

RUN git clone https://github.com/snhobbs/kicad-make/ --recurse-submodules --single-branch -b v9 kicad-make
RUN . /usr/share/venv/bin/activate && cd /usr/share/kicad-make/libs/InteractiveHtmlBom && pip install .
RUN . /usr/share/venv/bin/activate && cd /usr/share/kicad-make/libs/kicad-testpoints && pip install .

WORKDIR /home/${user}

# Default command
CMD ["bash"]
