# Work Journal Project Stack

To deploy the Work Journal docker container follow these steps:

If running from command line on the server

- copy example.env to .env `cp -v example.env .env`
- change the values in .env file
- run `docker compose up -d` command

If running from Portainer Server Interface

- copy/paste the compose.yaml content in the new stack editor
- change the `${HOSTNAME}` to the hostname of your server or any name you choose
- add each environment variable in the dedicated fields `name` and `value`
- press the `Deploy the stack` button
