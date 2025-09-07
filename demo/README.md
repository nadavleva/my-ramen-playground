# RamenDR Demo

Welcome to the organized RamenDR demo structure!

## Folder Structure

- **docs/**: All documentation and guides
- **scripts/**: Executable scripts for setup and demos  
- **yaml/**: YAML configuration files and templates
- **monitoring/**: Real-time monitoring and status scripts

## Quick Start

### For MINIKUBE (Recommended for laptops):
```bash
cd scripts/
./minikube_comprehensive-demo.sh --auto
```

### For KIND (Docker-based):
```bash
cd scripts/  
./kind_ramendr-demo.sh
```

## Monitoring Your Demo
```bash
cd monitoring/
./minikube_monitoring.sh    # For MINIKUBE
./kind_monitoring.sh        # For KIND
```

## Documentation

- **MINIKUBE_README.md** - MINIKUBE setup guide
- **KIND_README.md** - KIND setup guide  
- **DEMO_FLOW_GUIDE.md** - Step-by-step demo walkthrough
- **RAMENDR_ARCHITECTURE_GUIDE.md** - Technical architecture overview
- **MINIKUBE_TROUBLESHOOTING_GUIDE.md** - 🔧 Complete troubleshooting guide for connectivity & S3 issues

## File Naming Convention

- **minikube_**: Scripts and docs specific to MINIKUBE
- **kind_**: Scripts and docs specific to KIND
- **Generic files**: Work with both platforms

