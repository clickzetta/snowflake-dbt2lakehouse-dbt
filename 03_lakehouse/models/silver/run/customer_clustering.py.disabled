import numpy as np
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler


def model(dbt, session):
    """
    SILVER RUN: Customer clustering using Python and scikit-learn.

    Migration notes:
      Snowflake: import snowflake.snowpark as snowpark; session: snowpark.Session
                 packages=['snowflake-snowpark-python', 'joblib']
                 Stored procedure (sproc.register) for parallel execution
      ClickZetta: from clickzetta_zettapark.session import Session
                  session API is compatible (session.sql, .to_pandas, .createDataFrame)
                  Stored procedures not supported — parallel logic removed,
                  replaced with standard pandas/sklearn processing.
    """
    dbt.config(
        materialized="table",
        tags=["silver", "run", "python", "ml"],
        packages=["scikit-learn", "pandas", "numpy"],
    )

    customer_df = dbt.ref("customer_segments").to_pandas()

    features = ["ACCOUNT_BALANCE", "BALANCE_PERCENTILE", "BALANCE_RANK_IN_NATION"]
    X = customer_df[features].copy().fillna(customer_df[features].mean())

    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    n_clusters = 5
    kmeans = KMeans(n_clusters=n_clusters, random_state=42, n_init=10)
    clusters = kmeans.fit_predict(X_scaled)

    customer_df["ML_CLUSTER"] = clusters
    customer_df["CLUSTER_NAME"] = customer_df["ML_CLUSTER"].map({
        0: "High Value Stable",
        1: "Premium Elite",
        2: "Growth Potential",
        3: "Standard Base",
        4: "At Risk",
    })

    distances = [
        np.linalg.norm(X_scaled[i] - kmeans.cluster_centers_[clusters[i]])
        for i in range(len(X_scaled))
    ]
    customer_df["DISTANCE_TO_CLUSTER_CENTER"] = distances
    customer_df["IS_CLUSTER_OUTLIER"] = (
        customer_df["DISTANCE_TO_CLUSTER_CENTER"]
        > customer_df["DISTANCE_TO_CLUSTER_CENTER"].quantile(0.95)
    )
    customer_df["ML_CONFIDENCE_SCORE"] = 1 - (
        customer_df["DISTANCE_TO_CLUSTER_CENTER"]
        / customer_df["DISTANCE_TO_CLUSTER_CENTER"].max()
    )
    customer_df["ML_MODEL_VERSION"]      = "1.0"
    customer_df["CLUSTERING_ALGORITHM"]  = "KMeans"
    customer_df["N_CLUSTERS_USED"]       = n_clusters
    customer_df["FEATURES_USED"]         = str(features)

    return session.createDataFrame(customer_df)
