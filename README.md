# simple_enrollment

This script is designed to launch policies just after enrollment of a machine on Jamf.

## How to use

Just create a policy with following parameters :

* Parameter 4 : API username  
  Create a user in Jamf console dedicated for running the policies and script.

* Parameter 5 : Encoded password  
  Use the script [here](https://github.com/brysontyrrell/EncryptedStrings) to generate the parameters
* Parameter 6 : Salt string

* Parameter 7 : Passphrase

* Parameter 8 : testingMode (must be true of false)  
  In testing mode set to true, the policies are not run, there will be a sleep between each policy. That will help you to check the enrollment before running it live.

* Parameter 9 : welcomePopup (must be true of false)  
  Displays a welcome popup to your users. You can change text displayed by modifying lines 77-78.

Also change the categoryName variable line 19. It must reflect the category where all your policies are stored.

The script will run all the policies in order. I suggest you name your policies with a starting number, like "1.0-Policy1"

