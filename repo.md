# General information

1. Source code of OpenHands-Cloud is at tmp/OpenHands-Cloud folder.
Important files location:

- tmp/OpenHands-Cloud/charts/openhands/README.md
- tmp/OpenHands-Cloud/charts/openhands/values.yaml

## OpenHands chart image source code

Source code of extracted OpenHands image from charts is located at `tmp/openhands-extracted`

## Templates

The templates yaml.j2 are used and yaml files are auto-generated.
Templates are located in 'templates' folder.

# Deployment

if
```
flux get hr -n openhands openhands
```
has MESSAGE of running 'upgrade', it doesn't mean that the deployment is successful.
You need to check additional logs.