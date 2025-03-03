# Setting Up a VM for Testing

## When Creating a New VM

For testing purposes and to avoid modifying our production server, setting up your own VM is highly recommended. To ease this process and to prevent making the same mistakes I did, here is a simple guide. This guide does not cover setting up the VM in Azure but focuses on obtaining the correct version of Ruby and the bundle installer so that you can run the application in the cloud.

## Updating Your VM

Once you have successfully created your VM and gained access via SSH, run the following command:

```sh
sudo do-release-upgrade
```

This will take some time as it updates your entire Ubuntu OS. Click "Yes" for all steps in the installation.

After this, update your system packages:

```sh
sudo apt update
```

## Installing Ruby and Required Dependencies

Run the following command to install essential packages:

```sh
sudo apt install -y build-essential libsqlite3-dev libssl-dev
```

Then install the necessary Ruby gems:

```sh
sudo bundle install
```

The Bundler should upgrade itself. If this does not happen and you encounter issues installing Ruby gems, try:

```sh
bundle update --bundler
```

## Configuring the Azure VM for Ruby Applications

Your server is almost ready to run the Ruby Sinatra application. The last step is to configure your VM in Azure:

1. Navigate to **Network Settings**.
2. Add an **Inbound Port Rule** for port `4568` (or the port you are using for your Ruby application).

## Running the Ruby Application

Navigate to your Sinatra application directory and run:

```sh
ruby app.rb
```

## Conclusion

Congratulations! You now have our project running on your own VM.
