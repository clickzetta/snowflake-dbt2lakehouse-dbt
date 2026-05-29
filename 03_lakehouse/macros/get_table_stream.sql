{#
  ClickZetta replacement for Snowflake's get_stream() macro.

  Snowflake: SHOW STREAMS / CREATE STREAM ... SHOW_INITIAL_ROWS = TRUE
  ClickZetta: CREATE TABLE STREAM ... WITH PROPERTIES ('TABLE_STREAM_MODE' = 'STANDARD')

  Note: requires dbt-clickzetta >= 1.6.3 — this.database returned None in earlier versions.
  With 1.6.3, {{ this }} renders correctly as schema.table.

  Usage: {{ get_table_stream(ref('dim_customers')) }}
#}
{%- macro get_table_stream(table, stream_name=( (this.alias or this.name) ~ "_ts" )) -%}
    {%- set stream_full = this.schema ~ "." ~ stream_name -%}

    {% if execute and flags.WHICH in ('run', 'build') %}
        {%- set stream_create_statement -%}
        create table stream if not exists {{ stream_full }}
        on table {{ table }}
        with properties ('TABLE_STREAM_MODE' = 'STANDARD')
        {%- endset -%}
        {%- do log("Ensuring table stream exists: " ~ stream_full, info=true) -%}
        {%- do run_query(stream_create_statement) -%}
    {%- endif -%}

    {{ return(stream_full) }}
{%- endmacro -%}
