## Installing and Launching for Development

### Install prerequisites

Install [Git](http://git-scm.com/), [Vagrant](http://www.vagrantup.com/) 1.2.7,
[Virtualbox](http://www.virtualbox.org/) 4.2.16 and [pip](https://pip.pypa.io/).
Mac OS X 10.9 "Mavericks" users should install Vagrant 1.3.5 and VirtualBox 4.3.2.

You may also have to import the right VM image:

    $ vagrant box add precise32 http://files.vagrantup.com/precise32.box

### Configure and Load Virtual Machine

    $ git clone git@github.com:parklab/refinery-deployment.git
    $ cd refinery-deployment

Create a virtual environment (optional but recommended):

    $ mkvirtualenv -a $(pwd) refinery-deployment

Install Python dependencies:

    $ pip install -r requirements.txt

Configure VM and deploy Refinery:

    $ vagrant up
    $ fab vm deploy

### Troubleshooting

If you run into a build error in OS X when trying to install Python dependencies:

    $ export C_INCLUDE_PATH=/usr/local/include
