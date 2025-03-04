# Deleting the Database from our Public Repository

## Initial considerations

Before starting this exercise, I have researched various ways to solve the problem, that our database shouldn't be pushed to our public GitHub repository.

I found that there a various ways to solve this, all including that the database path should be added to our .gitignore file, to prevent Git from tracking it.

Then I found these various solutions:
1. Using seeds
2. Manually copy with SCP
3. Use a Private Repository
4. Switching to a managed database service like Azure Database for PostgresSQL or MySQL
5. Containerization with volumes

If this was a true production server in a company, it would be a really good idea to upgrade from SQLLite to a managed database service. As this is a part of the curriculum of the course in one of the lectures in the future, we will leave it to be SQLLite from now on.

As the next part of this course is containerization, we will just go with a simple approach of moving the database to a safe location outside of the repo folder on our production server, and using git -rm cache command to remove it from our gitrepository, and adding it to our .gitignore.

Currently we are using this command before running our application on the server:
export DATABASE_PATH="/home/azureuser/path/yourdatabase.db"

This has to be done manually everytime closing the Puma Sinatra server. We will look into ways of automating this, as that would make better sense. 

## Backup your existing data

Before doing anything, make sure that your current database file from your GitHub repository is persisted elsewhere. This shouldn’t be an issue as all group members should have it locally, and for now, it can be found in the commit history.

## Remove the database file from the repository

Remove the file from Git’s tracking without deleting it from our local system. This is done by running the following command, with paths edited to fit your project structure:

```sh
git rm --cached path/to/database.db
```

### Commit the changes:

```sh
git add .  # OR
git add -A
git commit -m "Remove database file from repository"
```

### Push the changes:

```sh
git push
```

## Adding the database file to your .gitignore

Inside of your `.gitignore` file, add the following:

```
/path/to/database.db
```

## On our production server, move the database to a secure location

Run the following command, adjusting the paths accordingly:

```sh
mv /path/to/your/repo/database.db /path/to/secure/location/database.db
```

## Update your Ruby code to adhere to the changes we just made

Now that we have moved our database, our project won’t run as it can’t find the database anymore. To adjust this, update your code accordingly. Example code snippet:

```ruby
DB_PATH = if ENV['RACK_ENV'] == 'test'
  # Use a separate test database
  File.join(__dir__, 'test', 'test_whoknows.db')
elsif ENV['DATABASE_PATH']
  # Use the path from an environment variable if provided
  ENV['DATABASE_PATH']
else
  # Fallback for development
  File.join(__dir__, 'whoknows.db')
end
```

This ensures that you can still run your project locally as well as on your production server.

## On the production server, set the `DATABASE_PATH` accordingly and export it

For our production server to know where our database is located, simply run:

```sh
export DATABASE_PATH="/home/azureuser/path/yourdatabase.db"
```

or preferrable add it to your .env file by:
```sh
nano .env
```

and then inside your .env file add:
DATABASE_PATH="/home/azureuser/path/yourdatabase.db"
