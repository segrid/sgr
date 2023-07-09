# SeGridRouter
> This project is in initial stage of development and stability tests. You are welcome to try out and report issues at https://github.com/segrid/sgr/issues. All issues will be attended to promptly. Source code will be made public in due course.

> This is a project developed by testers who have used selenoid for a very long time are are impressed with the stability of the project. We intend to 10x the power selenoid provides, by adding auto scaling using instances across AWS/ Azure/ GCP cloud providers.

SeGrid Router enables auto scaling selenoid grid by managing launch and termination of cloud instances automatically based on demand. This include self installation of [ggr](https://github.com/aerokube/ggr) and [selenoid](https://github.com/aerokube/selenoid) without any manual steps needed.

## Getting started
You can chose to either launch a pre-configured machine from AWS marketplace, and install manually on a pre-launched ubuntu instance.

### Install from AWS marketplace
Head over to [product page](https://aws.amazon.com/marketplace/seller-profile?id=b451fadc-5a20-42b1-8db6-32138f439789&ref=dtl_B09NMHRT89) and launch an EC2 instance.

### Install manually
Launch latest stable ubuntu based instance and run following commands to setup:
```
curl -fsSL https://raw.githubusercontent.com/segrid/sgr/main/install.sh -o install.sh
sudo /bin/bash ./install.sh
```

## Configure for initial usage
Once installation is complete, application will be accessible at http://\<private-ip\>:8080/segrid/