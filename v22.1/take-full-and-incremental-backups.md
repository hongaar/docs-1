---
title: Take Full and Incremental Backups
summary: Learn how to back up and restore a CockroachDB cluster.
toc: true
docs_area: manage
---

Because CockroachDB is designed with high fault tolerance, backups are primarily needed for [disaster recovery](disaster-recovery.html) (i.e., if your cluster loses a majority of its nodes). Isolated issues (such as small-scale node outages) do not require any intervention. However, as an operational best practice, **we recommend taking regular backups of your data**.

There are two main types of backups:

- [Full backups](#full-backups)
- [Incremental backups](#incremental-backups)

You can use the [`BACKUP`](backup.html) statement to efficiently back up your cluster's schemas and data to popular cloud services such as AWS S3, Google Cloud Storage, or NFS, and the [`RESTORE`](restore.html) statement to efficiently restore schema and data as necessary. For more information, see [Use Cloud Storage for Bulk Operations](use-cloud-storage-for-bulk-operations.html).

{% include {{ page.version.version }}/backups/backup-to-deprec.md %}

{{site.data.alerts.callout_success}}
 You can create [schedules for periodic backups](manage-a-backup-schedule.html) in CockroachDB. We recommend using scheduled backups to automate daily backups of your cluster.
{{site.data.alerts.end}}

## Backup collections

 A _backup collection_ defines a set of backups and their metadata. The collection can contain multiple full backups and their subsequent [incremental backups](#incremental-backups). The path to a backup is created using a date-based naming scheme and stored at the [collection URI](backup.html#collectionURI-param) passed with the `BACKUP` statement.

There are some specific cases where part of the collection data is stored at a different URI:

- A [locality-aware backup](take-and-restore-locality-aware-backups.html). The backup collection will be stored according to the URIs passed with the `BACKUP` statement: `BACKUP INTO LATEST IN {collectionURI}, {localityURI}, {localityURI}`. Here, the `collectionURI` represents the default locality.
- As of v22.1, it is possible to store incremental backups at a [different URI](#incremental-backups-with-explicitly-specified-destinations) to the related full backup. This means that one or multiple storage locations can hold one backup collection.

By default, full backups are stored at the root of the collection's URI in a date-based path, and incremental backups are stored in the `/incrementals` directory. The following example shows a backup collection created using these default values, where all backups reside in one storage bucket:

~~~
Collection URI:
|—— 2022
  |—— 02
    |—— 09-155340.13/
      |—— Full backup files
[...]
|—— incrementals
  |—— 2022
  |—— 02
    |—— 25-172907.21/
      |—— 20220325
        |—— 17921.23
          |—— incremental backup files
~~~

[`SHOW BACKUPS IN {collectionURI}`](show-backup.html#view-a-list-of-the-available-full-backup-subdirectories) will display a list of the full backup subdirectories at the collection's URI.

<a name="incremental-location-structure"></a> Alternately, the following directories also constitute a backup collection. There are multiple backups in two separate URIs. Each individual backup is a full backup and its related incremental backup(s). Despite using the [`incremental_location`](#incremental-backups-with-explicitly-specified-destinations) option to store the incremental backup in an alternative location, that incremental backup is still part of this backup collection as it depends on the full backup in the first cloud storage bucket:

~~~
Collection URI
|—— 2022
  |—— 02
    |—— 09-155340.13/
      |—— Full backup files
      |—— 20220210/
        |—— 155530.50/
        |—— 16-143018.72/
          |—— Full backup files
|—— incrementals
  |—— 2022
  |—— 02
    |—— 25-172907.21/
      |—— 20220325
        |—— 17921.23
          |—— incremental backup files
~~~

~~~
Explicit Incrementals URI
|—— 2022
  |—— 02
    |—— 25-172907.21/
      |—— 20220325
        |—— 17921.23
          |—— incremental_location backup files
~~~

In the examples on this page, `{collectionURI}` is a placeholder for the storage location that will contain the example backup.

## Full backups

Full backups are now available to both core and Enterprise users.

Full backups contain an un-replicated copy of your data and can always be used to restore your cluster. These files are roughly the size of your data and require greater resources to produce than incremental backups. You can take full backups as of a given timestamp. Optionally, you can include the available [revision history](take-backups-with-revision-history-and-restore-from-a-point-in-time.html) in the backup.

In most cases, **it's recommended to take nightly full backups of your cluster**. A cluster backup allows you to do the following:

- Restore table(s) from the cluster
- Restore database(s) from the cluster
- Restore a full cluster

Backups will export [Enterprise license keys](enterprise-licensing.html) during a [full cluster backup](backup.html#backup-a-cluster). When you [restore](restore.html) a full cluster with an Enterprise license, it will restore the Enterprise license of the cluster you are restoring from.

{% include {{ page.version.version }}/backups/file-size-setting.md %}

### Take a full backup

To perform a full cluster backup, use the [`BACKUP`](backup.html) statement:

{% include_cached copy-clipboard.html %}
~~~ sql
> BACKUP INTO '{collectionURI}';
~~~

To restore a backup, use the [`RESTORE`](restore.html) statement, specifying what you want to restore as well as the [collection's](#backup-collections) URI:

- To restore the latest backup of a table:

    {% include_cached copy-clipboard.html %}
    ~~~ sql
    > RESTORE TABLE bank.customers FROM LATEST IN '{collectionURI}';
    ~~~

- To restore the latest backup of a database:

    {% include_cached copy-clipboard.html %}
    ~~~ sql
    > RESTORE DATABASE bank FROM LATEST IN '{collectionURI}';
    ~~~

- To restore the latest backup of your full cluster:

    {% include_cached copy-clipboard.html %}
    ~~~ sql
    > RESTORE FROM LATEST IN '{collectionURI}';
    ~~~

    {{site.data.alerts.callout_info}}
    A full cluster restore can only be run on a target cluster that has **never** had user-created databases or tables.
    {{site.data.alerts.end}}

- To restore a backup from a specific subdirectory:

    {% include_cached copy-clipboard.html %}
    ~~~ sql
    > RESTORE DATABASE bank FROM {subdirectory} IN '{collectionURI}';
    ~~~

To view the available backup subdirectories, use [`SHOW BACKUPS`](show-backup.html).

## Incremental backups

{{site.data.alerts.callout_info}}
To take incremental backups, you need an [Enterprise license](enterprise-licensing.html).
{{site.data.alerts.end}}

If your cluster grows too large for nightly [full backups](#full-backups), you can take less frequent full backups (e.g., weekly) with nightly incremental backups. Incremental backups are storage efficient and faster than full backups for larger clusters.

Incremental backups are smaller and faster to produce than full backups because they contain only the data that has changed since a base set of backups you specify (which must include one full backup, and can include many incremental backups). You can take incremental backups either as of a given timestamp or with full [revision history](take-backups-with-revision-history-and-restore-from-a-point-in-time.html).

{{site.data.alerts.callout_danger}}
Incremental backups can only be created within the garbage collection period of the base backup's most recent timestamp. This is because incremental backups are created by finding which data has been created or modified since the most recent timestamp in the base backup––that timestamp data, though, is deleted by the garbage collection process.

You can configure garbage collection periods using the `ttlseconds` [replication zone setting](configure-replication-zones.html#gc-ttlseconds).
{{site.data.alerts.end}}

### Take an incremental backup

Periodically run the [`BACKUP`][backup] command to take a full backup of your cluster:

{% include_cached copy-clipboard.html %}
~~~ sql
> BACKUP INTO '{collectionURI}';
~~~

Then, create nightly incremental backups based off of the full backups you've already created. To append an incremental backup to the most recent full backup created at the [collection's](#backup-collections) URI, use the `LATEST` syntax:

{% include_cached copy-clipboard.html %}
~~~ sql
> BACKUP INTO LATEST IN '{collectionURI}';
~~~

<span class="version-tag">New in v22.1:</span> This will add the incremental backup to the default `/incrementals` directory at the root of the backup collection's directory. With incremental backups in the `/incrementals` directory, you can apply different lifecycle/retention policies from cloud storage providers to the `/incrementals` directory as needed.

{{site.data.alerts.callout_info}}
In v21.2 and earlier, incremental backups were stored in the same directory as their full backup (i.e., `collectionURI/subdirectory`). If an incremental backup command points to a subdirectory with incremental backups created in v21.2 and earlier, v22.1 will write the incremental backup to the v21.2 default location. To use the prior behavior on a backup that does not already contain incremental backups in the full backup subdirectory, use the `incremental_location` option, as shown in this [example](#backup-earlier-behavior).
{{site.data.alerts.end}}

If it's ever necessary, you can then use the [`RESTORE`][restore] statement to restore your cluster, database(s), and/or table(s). Restoring from incremental backups requires previous full and incremental backups.

To restore from the latest backup in the collection, stored in the default `/incrementals` collection subdirectory, run:

{% include_cached copy-clipboard.html %}
~~~ sql
> RESTORE FROM LATEST IN '{collectionURI}';
~~~

To restore from a specific backup in the collection:

{% include_cached copy-clipboard.html %}
~~~ sql
> RESTORE FROM '{subdirectory}' IN '{collectionURI}';
~~~

{{site.data.alerts.callout_info}}
`RESTORE` will re-validate [indexes](indexes.html) when [incremental backups](take-full-and-incremental-backups.html) are created from an older version (v20.2.2 and earlier or v20.1.4 and earlier), but restored by a newer version (v21.1.0+). These earlier releases may have included incomplete data for indexes that were in the process of being created.
{{site.data.alerts.end}}

## Incremental backups with explicitly specified destinations

<span class="version-tag">New in v22.1:</span> To explicitly control where your incremental backups go, use the [`incremental_location`](backup.html#options) option. By default, incremental backups are stored in the `/incrementals` subdirectory at the root of the collection. However, there are some advanced cases where you may want to store incremental backups in a different storage location.

In the following examples, the `{collectionURI}` specifies the storage location containing the full backup. The `{explicit_incrementalsURI}` is the alternative location that you can store an incremental backup:

{% include_cached copy-clipboard.html %}
~~~ sql
BACKUP INTO LATEST IN '{collectionURI}' AS OF SYSTEM TIME '-10s' WITH incremental_location = '{explicit_incrementalsURI}';
~~~

Although the incremental backup will be in a different storage location, it is still part of the logical [backup collection](#backup-collections).

A full backup must be present in the `{collectionURI}` in order to take an incremental backup to the alternative `{explicit_incrementalsURI}`. If there isn't a full backup present in `{collectionURI}` when taking an incremental backup with `incremental_location`, the error `path does not contain a completed latest backup` will be returned.

For details on the backup directory structure when taking incremental backups with `incremental_location`, see this [incremental location directory structure](#incremental-location-structure) example.

<a name="backup-earlier-behavior"></a>To take incremental backups that are [stored in the same way as v21.2](../v21.2/take-full-and-incremental-backups.html#backup-collections) and earlier, you can use the `incremental_location` option. You can specify the same `collectionURI` with `incremental_location` and the backup will place the incremental backups in a date-based path under the full backup, rather than in the default `/incrementals` directory:

~~~ sql
BACKUP INTO LATEST IN '{collectionURI}' AS OF SYSTEM TIME '-10s' WITH incremental_location = '{collectionURI}';
~~~

When you append incrementals to this backup, they will continue to be stored in a date-based path under the full backup.

To restore an incremental backup that was taken using the [`incremental_location` option](restore.html#incr-location), you must run `RESTORE` with the full backup's location and the `incremental_location` option referencing the location passed in the original `BACKUP` statement:

~~~ sql
RESTORE TABLE movr.users FROM LATEST IN '{collectionURI}' WITH incremental_location = '{explicit_incrementalsURI}';
~~~

For details on cloud storage URLs, see [Use Cloud Storage for Bulk Operations](use-cloud-storage-for-bulk-operations.html).

## Examples

<div class="filters clearfix">
  <button class="filter-button" data-scope="s3">Amazon S3</button>
  <button class="filter-button" data-scope="azure">Azure Storage</button>
  <button class="filter-button" data-scope="gcs">Google Cloud Storage</button>
</div>

{% include {{ page.version.version }}/backups/bulk-auth-options.md %}

<section class="filter-content" markdown="1" data-scope="s3">

### Automated full backups

Both core and Enterprise users can use backup scheduling for full backups of clusters, databases, or tables. To create schedules that only take full backups, include the `FULL BACKUP ALWAYS` clause. For example, to create a schedule for taking full cluster backups:

{% include_cached copy-clipboard.html %}
~~~ sql
> CREATE SCHEDULE core_schedule_label
  FOR BACKUP INTO 's3://{BUCKET NAME}/{PATH}?AWS_ACCESS_KEY_ID={KEY ID}&AWS_SECRET_ACCESS_KEY={SECRET ACCESS KEY}'
    RECURRING '@daily'
    FULL BACKUP ALWAYS
    WITH SCHEDULE OPTIONS first_run = 'now';
~~~
~~~
     schedule_id     |        name         | status |         first_run         | schedule |                                                                                       backup_stmt
---------------------+---------------------+--------+---------------------------+----------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  588799238330220545 | core_schedule_label | ACTIVE | 2020-09-11 00:00:00+00:00 | @daily   | BACKUP INTO 's3://{BUCKET NAME}/{PATH}?AWS_ACCESS_KEY_ID={KEY ID}&AWS_SECRET_ACCESS_KEY={SECRET ACCESS KEY}' WITH detached
(1 row)
~~~

</section>

<section class="filter-content" markdown="1" data-scope="azure">

### Automated full backups

Both core and Enterprise users can use backup scheduling for full backups of clusters, databases, or tables. To create schedules that only take full backups, include the `FULL BACKUP ALWAYS` clause. For example, to create a schedule for taking full cluster backups:

{% include_cached copy-clipboard.html %}
~~~ sql
> CREATE SCHEDULE core_schedule_label
  FOR BACKUP INTO 'azure://{CONTAINER NAME}?AZURE_ACCOUNT_NAME={ACCOUNT NAME}&AZURE_ACCOUNT_KEY={URL-ENCODED KEY}'
    RECURRING '@daily'
    FULL BACKUP ALWAYS
    WITH SCHEDULE OPTIONS first_run = 'now';
~~~
~~~
     schedule_id     |        name         | status |         first_run         | schedule |                                                                                       backup_stmt
---------------------+---------------------+--------+---------------------------+----------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  588799238330220545 | core_schedule_label | ACTIVE | 2020-09-11 00:00:00+00:00 | @daily   | BACKUP INTO 'azure://{CONTAINER NAME}?AZURE_ACCOUNT_NAME={ACCOUNT NAME}&AZURE_ACCOUNT_KEY={URL-ENCODED KEY}' WITH detached
(1 row)
~~~

</section>

<section class="filter-content" markdown="1" data-scope="gcs">

### Automated full backups

Both core and Enterprise users can use backup scheduling for full backups of clusters, databases, or tables. To create schedules that only take full backups, include the `FULL BACKUP ALWAYS` clause. For example, to create a schedule for taking full cluster backups:

{% include_cached copy-clipboard.html %}
~~~ sql
> CREATE SCHEDULE core_schedule_label
  FOR BACKUP INTO 'gs://{BUCKET NAME}/{PATH}?AUTH=specified&CREDENTIALS={ENCODED KEY}'
    RECURRING '@daily'
    FULL BACKUP ALWAYS
    WITH SCHEDULE OPTIONS first_run = 'now';
~~~
~~~
     schedule_id     |        name         | status |         first_run         | schedule |                                                                                       backup_stmt
---------------------+---------------------+--------+---------------------------+----------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  588799238330220545 | core_schedule_label | ACTIVE | 2020-09-11 00:00:00+00:00 | @daily   | BACKUP INTO 'gs://{BUCKET NAME}/{PATH}?AUTH=specified&CREDENTIALS={ENCODED KEY}' WITH detached
(1 row)
~~~

</section>

For more examples on how to schedule backups that take full and incremental backups, see [`CREATE SCHEDULE FOR BACKUP`](create-schedule-for-backup.html).

### Advanced examples

{% include {{ page.version.version }}/backups/advanced-examples-list.md %}

{{site.data.alerts.callout_info}}
To take incremental backups, backups with revision history, locality-aware backups, and encrypted backups, you need an [Enterprise license](enterprise-licensing.html).
{{site.data.alerts.end}}

## See also

- [`BACKUP`][backup]
- [`RESTORE`][restore]
- [Take and Restore Encrypted Backups](take-and-restore-encrypted-backups.html)
- [Take and Restore Locality-aware Backups](take-and-restore-locality-aware-backups.html)
- [Take Backups with Revision History and Restore from a Point-in-time](take-backups-with-revision-history-and-restore-from-a-point-in-time.html)
- [`IMPORT`](migration-overview.html)
- [Use the Built-in SQL Client](cockroach-sql.html)
- [`cockroach` Commands Overview](cockroach-commands.html)

<!-- Reference links -->

[backup]:  backup.html
[restore]: restore.html
