FROM kicad/kicad:8.0

ENV DEBIAN_FRONTEND=noninteractive

USER root

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
    && /opt/venv/bin/pip install git+https://github.com/snhobbs/kicad-xyrs.git@master \
    && /opt/venv/bin/pip install git+https://github.com/snhobbs/kicad-testpoints.git@master \
    && /opt/venv/bin/pip install git+https://github.com/snhobbs/InteractiveHtmlBom.git@master

# Install make
RUN apt-get update && apt-get install -y \
    make \
    xvfb \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y \
    fonts-freefont-ttf \
        && rm -rf /var/lib/apt/lists/*

# Set environment variables to use the virtual environment
ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONPATH="/usr/lib/python3/dist-packages"
