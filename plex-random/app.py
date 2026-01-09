#!/usr/bin/env python3
"""Plex Random Player - Play random movies or TV episodes on your Plex clients."""

import os
import random
from flask import Flask, render_template, request, jsonify
from plexapi.server import PlexServer
from plexapi.exceptions import NotFound

app = Flask(__name__)

# Configuration from environment
PLEX_URL = os.environ.get('PLEX_URL', 'http://localhost:32400')
PLEX_TOKEN = os.environ.get('PLEX_TOKEN', '')

def get_plex():
    """Get Plex server connection."""
    return PlexServer(PLEX_URL, PLEX_TOKEN)

def get_clients():
    """Get list of available Plex clients from multiple sources."""
    plex = get_plex()
    clients = []
    seen_ids = set()

    # Source 1: Direct clients (devices that have advertised to server)
    for client in plex.clients():
        if client.machineIdentifier not in seen_ids:
            seen_ids.add(client.machineIdentifier)
            clients.append({
                'name': client.title,
                'type': 'client',
                'identifier': client.machineIdentifier,
                'product': getattr(client, 'product', 'Unknown'),
                'device': getattr(client, 'device', 'Unknown'),
                'source': 'direct'
            })

    # Source 2: Active sessions (currently playing devices)
    for session in plex.sessions():
        player = session.player
        if player.machineIdentifier not in seen_ids:
            seen_ids.add(player.machineIdentifier)
            clients.append({
                'name': player.title,
                'type': 'session',
                'identifier': player.machineIdentifier,
                'product': getattr(player, 'product', 'Unknown'),
                'device': getattr(player, 'device', 'Unknown'),
                'source': 'session'
            })

    # Source 3: Plex account resources (all registered devices)
    try:
        account = plex.myPlexAccount()
        for resource in account.resources():
            # Only include devices that can play media
            if resource.provides and 'player' in resource.provides:
                if resource.clientIdentifier not in seen_ids:
                    seen_ids.add(resource.clientIdentifier)
                    clients.append({
                        'name': resource.name,
                        'type': 'resource',
                        'identifier': resource.clientIdentifier,
                        'product': getattr(resource, 'product', 'Unknown'),
                        'device': getattr(resource, 'device', 'Unknown'),
                        'source': 'account'
                    })
    except Exception:
        pass  # Account access may fail, continue with other sources

    return clients

def find_client(plex, client_id):
    """Find a controllable client by ID from multiple sources."""
    # Try direct clients first (these are fully controllable)
    for client in plex.clients():
        if client.machineIdentifier == client_id:
            return client

    # Get client name from sessions or resources for lookup
    client_name = None

    # Check sessions for the client name
    for session in plex.sessions():
        if session.player.machineIdentifier == client_id:
            client_name = session.player.title
            break

    # Check resources for the client name
    if not client_name:
        try:
            account = plex.myPlexAccount()
            for resource in account.resources():
                if resource.clientIdentifier == client_id:
                    client_name = resource.name
                    break
        except Exception:
            pass

    # If we found a name, try to get controllable client by name
    if client_name:
        try:
            return plex.client(client_name)
        except Exception:
            pass

    # Try to connect via account resources directly
    try:
        account = plex.myPlexAccount()
        for resource in account.resources():
            if resource.clientIdentifier == client_id:
                try:
                    return resource.connect()
                except Exception:
                    pass
    except Exception:
        pass

    return None

def get_libraries():
    """Get movie and TV libraries."""
    plex = get_plex()
    libraries = {'movies': [], 'shows': []}

    for section in plex.library.sections():
        if section.type == 'movie':
            libraries['movies'].append({'key': section.key, 'title': section.title})
        elif section.type == 'show':
            libraries['shows'].append({'key': section.key, 'title': section.title})

    return libraries

def get_genres(library_key):
    """Get genres for a library."""
    plex = get_plex()
    section = plex.library.sectionByID(int(library_key))

    genres = set()
    for item in section.all():
        for genre in item.genres:
            genres.add(genre.tag)

    return sorted(list(genres))

def get_shows(library_key):
    """Get all shows in a TV library."""
    plex = get_plex()
    section = plex.library.sectionByID(int(library_key))

    shows = []
    for show in section.all():
        shows.append({'key': show.ratingKey, 'title': show.title})

    return sorted(shows, key=lambda x: x['title'])

def get_content_ratings(library_key):
    """Get content ratings for a library."""
    plex = get_plex()
    section = plex.library.sectionByID(int(library_key))

    ratings = set()
    for item in section.all():
        if item.contentRating:
            ratings.add(item.contentRating)

    return sorted(list(ratings))

@app.route('/')
def index():
    """Main page."""
    try:
        libraries = get_libraries()
        clients = get_clients()
        return render_template('index.html', libraries=libraries, clients=clients)
    except Exception as e:
        return render_template('error.html', error=str(e))

@app.route('/api/clients')
def api_clients():
    """Get available clients."""
    try:
        clients = get_clients()
        return jsonify({'success': True, 'clients': clients})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/libraries')
def api_libraries():
    """Get available libraries."""
    try:
        libraries = get_libraries()
        return jsonify({'success': True, 'libraries': libraries})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/genres/<library_key>')
def api_genres(library_key):
    """Get genres for a library."""
    try:
        genres = get_genres(library_key)
        return jsonify({'success': True, 'genres': genres})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/shows/<library_key>')
def api_shows(library_key):
    """Get shows for a TV library."""
    try:
        shows = get_shows(library_key)
        return jsonify({'success': True, 'shows': shows})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/ratings/<library_key>')
def api_ratings(library_key):
    """Get content ratings for a library."""
    try:
        ratings = get_content_ratings(library_key)
        return jsonify({'success': True, 'ratings': ratings})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/play/movie', methods=['POST'])
def play_random_movie():
    """Play a random movie."""
    try:
        data = request.json
        client_id = data.get('client_id')
        library_key = data.get('library_key')
        unwatched_only = data.get('unwatched_only', False)
        genre = data.get('genre')
        content_rating = data.get('content_rating')

        plex = get_plex()
        section = plex.library.sectionByID(int(library_key))

        # Build filters
        filters = {}
        if unwatched_only:
            filters['unwatched'] = True
        if genre:
            filters['genre'] = genre
        if content_rating:
            filters['contentRating'] = content_rating

        # Get movies with filters
        if filters:
            movies = section.search(**filters)
        else:
            movies = section.all()

        if not movies:
            return jsonify({'success': False, 'error': 'No movies match your criteria'})

        # Pick random movie
        movie = random.choice(movies)

        # Try to find and control client
        client = find_client(plex, client_id)
        play_method = 'direct'

        if client:
            try:
                # Stop any current playback first for clean transition
                try:
                    client.stop()
                except Exception:
                    pass  # Ignore if stop fails (nothing playing)

                client.playMedia(movie)
            except Exception as e:
                # If direct control fails, try proxy through server
                try:
                    client.proxyThroughServer(True, plex)
                    try:
                        client.stop()
                    except Exception:
                        pass
                    client.playMedia(movie)
                    play_method = 'proxy'
                except Exception as e2:
                    # Return deep link as fallback
                    return jsonify({
                        'success': True,
                        'fallback': True,
                        'title': movie.title,
                        'year': movie.year,
                        'summary': movie.summary[:200] + '...' if len(movie.summary) > 200 else movie.summary,
                        'plex_url': f'{PLEX_URL}/web/index.html#!/server/{plex.machineIdentifier}/details?key={movie.key}',
                        'message': 'Could not auto-play. Click link to open in Plex.'
                    })
        else:
            # No controllable client - return deep link
            return jsonify({
                'success': True,
                'fallback': True,
                'title': movie.title,
                'year': movie.year,
                'summary': movie.summary[:200] + '...' if len(movie.summary) > 200 else movie.summary,
                'plex_url': f'{PLEX_URL}/web/index.html#!/server/{plex.machineIdentifier}/details?key={movie.key}',
                'message': 'Device not controllable. Click link to open in Plex.'
            })

        return jsonify({
            'success': True,
            'title': movie.title,
            'year': movie.year,
            'summary': movie.summary[:200] + '...' if len(movie.summary) > 200 else movie.summary,
            'play_method': play_method
        })

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/play/episode', methods=['POST'])
def play_random_episode():
    """Play a random TV episode."""
    try:
        data = request.json
        client_id = data.get('client_id')
        library_key = data.get('library_key')
        unwatched_only = data.get('unwatched_only', False)
        show_key = data.get('show_key')  # Specific show
        genre = data.get('genre')
        content_rating = data.get('content_rating')

        plex = get_plex()
        section = plex.library.sectionByID(int(library_key))

        episodes = []

        if show_key:
            # Get episodes from specific show
            show = plex.fetchItem(int(show_key))
            all_episodes = show.episodes()
            if unwatched_only:
                episodes = [ep for ep in all_episodes if not ep.isWatched]
            else:
                episodes = all_episodes

            if not episodes:
                return jsonify({'success': False, 'error': 'No episodes match your criteria'})

            episode = random.choice(episodes)
        else:
            # Optimized: Pick a random show first, then a random episode
            # This avoids loading all episodes from all shows
            show_filters = {}
            if genre:
                show_filters['genre'] = genre
            if content_rating:
                show_filters['contentRating'] = content_rating

            if show_filters:
                shows = section.search(**show_filters)
            else:
                shows = section.all()

            if not shows:
                return jsonify({'success': False, 'error': 'No shows match your criteria'})

            # Try up to 10 random shows to find one with matching episodes
            random.shuffle(shows)
            episode = None

            for show in shows[:10]:
                try:
                    all_episodes = show.episodes()
                    if unwatched_only:
                        matching = [ep for ep in all_episodes if not ep.isWatched]
                    else:
                        matching = all_episodes

                    if matching:
                        episode = random.choice(matching)
                        break
                except Exception:
                    continue

            if not episode:
                return jsonify({'success': False, 'error': 'No episodes match your criteria (tried 10 shows)'})

        # Try to find and control client
        client = find_client(plex, client_id)
        play_method = 'direct'

        episode_info = {
            'show': episode.grandparentTitle,
            'season': episode.parentIndex,
            'episode': episode.index,
            'title': episode.title,
            'summary': episode.summary[:200] + '...' if episode.summary and len(episode.summary) > 200 else (episode.summary or '')
        }

        if client:
            try:
                # Stop any current playback first for clean transition
                try:
                    client.stop()
                except Exception:
                    pass  # Ignore if stop fails (nothing playing)

                client.playMedia(episode)
            except Exception as e:
                # If direct control fails, try proxy through server
                try:
                    client.proxyThroughServer(True, plex)
                    try:
                        client.stop()
                    except Exception:
                        pass
                    client.playMedia(episode)
                    play_method = 'proxy'
                except Exception as e2:
                    # Return deep link as fallback
                    return jsonify({
                        'success': True,
                        'fallback': True,
                        **episode_info,
                        'plex_url': f'{PLEX_URL}/web/index.html#!/server/{plex.machineIdentifier}/details?key={episode.key}',
                        'message': 'Could not auto-play. Click link to open in Plex.'
                    })
        else:
            # No controllable client - return deep link
            return jsonify({
                'success': True,
                'fallback': True,
                **episode_info,
                'plex_url': f'{PLEX_URL}/web/index.html#!/server/{plex.machineIdentifier}/details?key={episode.key}',
                'message': 'Device not controllable. Click link to open in Plex.'
            })

        return jsonify({
            'success': True,
            **episode_info,
            'play_method': play_method
        })

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/health')
def health():
    """Health check endpoint."""
    try:
        plex = get_plex()
        return jsonify({'status': 'healthy', 'plex': 'connected'})
    except Exception as e:
        return jsonify({'status': 'unhealthy', 'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5050, debug=False)
