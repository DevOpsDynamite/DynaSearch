# KPI Report - DynaSearch 8th April 2025 

## CPU usage: Azure Production VM

![cpu.png](attachment:43ff0ac8-6edd-476b-861f-2d7a5c02684e:cpu.png)

We used Azure Monitor with percentage CPU metric and got this overview for the past 30 days. The average CPU load was 0.527%, with peaks reaching 1.6%.

These numbers indicates sufficient CPU resources for our application.

## CPU usage: Docker container

The Docker container has the following CPU usage stats:

![image.png](attachment:2199d17e-1976-44a5-9de2-236ad43c6d1a:image.png)

The stats indicate a low CPU usage on the Docker container, which aligns well with our current knowledge about Docker containers being lightweight.

## Registered Users

### Registered users per 8th April: **10**

To view the total number of registered users, we SSH’ed into our VM and changed the directory to where our database is located. From there, we called the SQLite3 command + the database name, which allows us to perform qeueries on our database. Then we inquired the total amount of registered users from the database, with the qeury: `SELECT COUNT (*) FROM users;`

## Unregistered Users

### Unregistered users per 8th April: Unkown

To view the number of unregistered users, we would have to set up nginx in order to access logs on how many unique users visits our website. Nginx registers IP-addresses, which makes it possible to calculate the accurate number.

## Active Users

### The total number of active users: Unknown

Since we are not logging user activity yet, we do not know the number of users who uses the application frequently. 

## Searches

### Average number of searches per day: Unknown

We could either log the number of searches using Nginx or Azure Application Insights. We have not decided how to approach this measure.

## Cost of the Infrastructure

The **total** cost of the infrastrucure since launch: **39.35 DKK**

The current **monthy** cost of the infrastucture: **15.08 DKK**

This number includes only the VM on Azure Cloud Services.

**Hosting on one.com:** From August 2025 the cost of hosting is will increase from **0 DKK to 119 DKK annually**, but we currently have a free subscription.

**Database:** We do not yet have a managed database on Azure. The estimated cost when this is implemented, would be: **116.26 DKK monthly**.

The **annual budget forecast** based on these numbers is calculated to: **1700 DKK**