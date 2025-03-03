# Deleting the Database from our Public Repository

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