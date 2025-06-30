FROM kicad/kicad:9.0

ENV DEBIAN_FRONTEND=noninteractive

# Create a non-root user
ARG ORIGINALUSER=kicad
ARG USERNAME=user
ARG UID=1000
ARG GID=1000

USER root
RUN usermod -l $USERNAME -d /home/$USERNAME -m -s /bin/bash $ORIGINALUSER  \
    && groupmod -n $USERNAME $ORIGINALUSER \
    && apt-get update && apt-get install -y sudo \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install Python, pip, and venv
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Create a Python virtual environment
RUN python3 -m venv /opt/venv

# Activate the virtual environment and install Python packages
RUN /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install git+https://github.com/snhobbs/kicad-testpoints.git \
    && /opt/venv/bin/pip install git+https://github.com/snhobbs/InteractiveHtmlBom.git

# Install make
RUN apt-get update && apt-get install -y \
    make \
    xvfb \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Set environment variables to use the virtual environment
ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONPATH="/usr/lib/python3/dist-packages"

# Set environment variables for the new user
ENV HOME=/home/${USERNAME}
WORKDIR /home/${USERNAME}
USER ${USERNAME}

CMD ["bash"]
