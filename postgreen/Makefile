LIBS_FOLDER = "./libs/"

install:
	curl -Ls -o ovh-api-bash-client.sh https://raw.githubusercontent.com/Nirva-Software/ovh-api-bash-client/master/ovh-api-bash-client.sh
	chmod +x /usr/local/bin/ovh-api-bash-client.sh
	
	curl -Ls -o $(LIBS_FOLDER)/JSON.sh --create-dirs https://github.com/dominictarr/JSON.sh/raw/master/JSON.sh
	chmod +x $(LIBS_FOLDER)/*

	curl -Ls -o backup_instance.sh https://raw.githubusercontent.com/Nirva-Software/NirvaApplicationPlatform/master/postgreen/backup_instance.sh
	curl -Ls -o send_email.sh https://raw.githubusercontent.com/Nirva-Software/NirvaApplicationPlatform/master/postgreen/send_email.sh
	curl -Ls -o log_rotation.sh https://raw.githubusercontent.com/Nirva-Software/NirvaApplicationPlatform/master/postgreen/log_rotation.sh
	chmod +x backup_instance.sh send_email.sh log_rotation.sh
	curl -Ls -o backup.config https://raw.githubusercontent.com/Nirva-Software/NirvaApplicationPlatform/master/postgreen/backup.config
