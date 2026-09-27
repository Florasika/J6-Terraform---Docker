"""
JOUR 6 / 10 — Terraform & Docker
Pipeline ETL monté dans le conteneur ETL par Terraform.
Toutes les variables d'env sont injectées par Terraform.
"""

import os, time, random, sys
import pandas as pd
from datetime import datetime, date
from sqlalchemy import create_engine, text

DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_PORT = os.getenv('DB_PORT', '5432')
DB_NAME = os.getenv('DB_NAME', 'etl_portfolio_dev')
DB_USER = os.getenv('DB_USER', 'admin')
DB_PWD  = os.getenv('DB_PASSWORD', '')
PROJET  = os.getenv('PROJET', 'etl_portfolio')
ENV     = os.getenv('ENV', 'dev')

DB_URL = f"postgresql://{DB_USER}:{DB_PWD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

def attendre_postgres(retries=20):
    engine = create_engine(DB_URL)
    for i in range(retries):
        try:
            with engine.connect() as c: c.execute(text("SELECT 1"))
            print(f"PostgreSQL prêt"); return engine
        except Exception:
            print(f"Attente ({i+1}/{retries})..."); time.sleep(3)
    raise ConnectionError("PostgreSQL inaccessible")

def run():
    print(f"Pipeline {PROJET} [{ENV}] démarré")
    random.seed(42)
    produits = ['Laptop Pro','Smartphone X','Tablette Air']
    prix     = {'Laptop Pro':1200,'Smartphone X':650,'Tablette Air':450}
    vendeurs = ['Alice','Karim','Lucie','Thomas','Nadia']

    engine = attendre_postgres()
    with engine.begin() as c:
        c.execute(text("""CREATE TABLE IF NOT EXISTS ventes (
            id SERIAL PRIMARY KEY, date TEXT, produit VARCHAR(50),
            vendeur VARCHAR(30), montant NUMERIC(10,2),
            marge NUMERIC(10,2), charge_le TEXT
        )"""))

    rows = [{'date':date.today().isoformat(),'produit':(p:=random.choice(produits)),
             'vendeur':random.choice(vendeurs),'montant':(m:=random.randint(1,8)*prix[p]),
             'marge':round(m*0.42,2),'charge_le':datetime.now().isoformat()}
            for _ in range(25)]

    df = pd.DataFrame(rows)
    today = date.today().isoformat()
    with engine.begin() as c: c.execute(text(f"DELETE FROM ventes WHERE date='{today}'"))
    df.to_sql('ventes', engine, if_exists='append', index=False)

    os.makedirs('/output', exist_ok=True)
    df.to_csv(f'/output/ventes_{today}.csv', index=False)

    print(f"Pipeline OK — {len(df)} lignes | CA: {df['montant'].sum():.0f}€")
    print(f"CSV: /output/ventes_{today}.csv")

if __name__ == '__main__':
    run()
